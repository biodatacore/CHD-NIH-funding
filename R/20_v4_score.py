"""20_v4_score.py -- score the adjudicated V4 review against the v2.3 pipeline.

Usage (from project root):
  python3 R/20_v4_score.py

Inputs:
  data/validation/v4_review_adjudicated.csv
  outputs/v2.3/chd_v4_review_ANSWER_KEY.xlsx

Output:
  outputs/v2.3/chd_v4_review_scoring_v2.3.xlsx

Reviewer CHD truth = Yes|Partly (primary) and Yes only (sensitivity check).
Unsure rows are excluded from metrics and reported.
Pipeline positive = v2.3 combined (tier 1 + tier 2).
Weighted = inverse-probability weights from the answer key (N_frame / n_sample);
CIs for weighted metrics and for kappa = stratified bootstrap (2,000 draws, seed 1).
Unweighted binomial metrics use Wilson 95% CIs.
Weighted metrics are reported for all strata and without A4 (rest-of-portfolio,
weight about 43,833), because A4's weight dominates specificity / accuracy / kappa.
This script does not change pipeline rules.
"""
import os
import re
import numpy as np
import pandas as pd
from math import sqrt
from openpyxl import load_workbook

RET = os.environ.get("CHD_V4_RETURNED", "data/validation/v4_review_adjudicated.csv")
KEYP = os.environ.get("CHD_KEY", "outputs/v2.3/chd_v4_review_ANSWER_KEY.xlsx")
OUTP = os.environ.get("CHD_SCORE_OUT", "outputs/v2.3/chd_v4_review_scoring_v2.3.xlsx")
CC = "CHD focus (Yes / Partly / No / Unsure)"
CA = "Age population (Pediatric / Adult / Both / Neither / Unclear)"
SEED, B = 1, 2000

try:
    R = pd.read_csv(RET, encoding="utf-8")
except UnicodeDecodeError:
    R = pd.read_csv(RET, encoding="latin1")
R = R[R["Review ID"].notna()].copy()
R["Review ID"] = R["Review ID"].astype(str).str.strip()
K = pd.read_excel(KEYP, sheet_name="Key")
if os.environ.get("CHD_RELABEL"):
    L = pd.read_pickle(os.environ["CHD_RELABEL"])[["FY", "FULL_PROJECT_NUM", "tier", "t2_route", "t1_drop"]]
    dropcols = [c for c in ["tier", "t2_route", "t1_drop"] if c in K.columns]
    K = K.drop(columns=dropcols).merge(L, on=["FY", "FULL_PROJECT_NUM"], how="left")
    K["tier"] = K.tier.fillna("Not CHD")
D = K.merge(R[["Review ID", "Project number", CC, CA, "Comments",
                "Reviewer code", "Review date (YYYY-MM-DD)"]],
            on="Review ID", how="left")
bad = D[D["Project number"] != D.FULL_PROJECT_NUM]
assert bad.empty, f"ID/project mismatch: {bad['Review ID'].tolist()}"
assert set(D["Review ID"]) == {f"V4-{i:03d}" for i in range(1, 201)}, "V4 IDs not complete"

D["rev"] = D[CC].astype(str).str.strip().str.capitalize()
D["age_raw"] = D[CA].astype(str).str.strip()
D["age"] = D.age_raw.replace({"neither": "Neither", "pediatric": "Pediatric"})
D["comments"] = D.Comments.fillna("").astype(str)
done = D.rev.isin(["Yes", "Partly", "No"])
n_unsure = int((D.rev == "Unsure").sum())
n_blank = int((~D.rev.isin(["Yes", "Partly", "No", "Unsure"])).sum())
print(f"answered {done.sum()} / {len(D)}; Unsure {n_unsure}; blank {n_blank}")

X = D[done].copy()
X["pp"] = X.tier != "Not CHD"


def metr(pp, rp, w):
    pp, rp, w = np.asarray(pp, bool), np.asarray(rp, bool), np.asarray(w, float)
    tp, fp, fn, tn = w[pp & rp].sum(), w[pp & ~rp].sum(), w[~pp & rp].sum(), w[~pp & ~rp].sum()
    n = tp + fp + fn + tn
    po = (tp + tn) / n if n else np.nan
    pe = ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / n ** 2 if n else np.nan
    f = lambda a, b: a / (a + b) if a + b > 0 else np.nan
    return dict(Sensitivity=f(tp, fn), Specificity=f(tn, fp), PPV=f(tp, fp), NPV=f(tn, fn),
                Accuracy=po, Kappa=(po - pe) / (1 - pe) if (pe is not np.nan and pe < 1) else np.nan,
                TP=tp, FP=fp, FN=fn, TN=tn)


def wilson(k, n, z=1.96):
    if n == 0 or pd.isna(k) or pd.isna(n):
        return (np.nan, np.nan)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)


def boot(pp, rp, w, st, B=B, seed=SEED):
    st = np.asarray(st)
    g = [np.where(st == s)[0] for s in pd.unique(st)]
    g = [x for x in g if len(x)]
    r = np.random.default_rng(seed)
    o = [metr(pp[b], rp[b], w[b]) for b in (np.concatenate([r.choice(x, len(x)) for x in g]) for _ in range(B))]
    return pd.DataFrame(o).quantile([.025, .975])


rows = []
frames = [
    ("all strata (portfolio)", X),
    ("without A4 rest-of-portfolio stratum", X[~X.stratum.str.startswith("A4")]),
]
for truth, tf in [("Yes|Partly", lambda s: s.isin(["Yes", "Partly"])),
                  ("Yes only", lambda s: s == "Yes")]:
    for frame, d in frames:
        rp = tf(d.rev).values
        pp = d.pp.values
        st = d.stratum.values
        for wl, w in [("unweighted", np.ones(len(d))), ("weighted", d.weight.values)]:
            if wl == "unweighted" and frame.startswith("without"):
                continue  # unweighted without A4 is not a primary figure; full unweighted already includes only 5 A4 rows
            m = metr(pp, rp, w)
            q = boot(pp, rp, w, st)
            den = {"Sensitivity": m["TP"] + m["FN"], "Specificity": m["TN"] + m["FP"],
                   "PPV": m["TP"] + m["FP"], "NPV": m["TN"] + m["FN"], "Accuracy": w.sum()}
            for k in ["Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa"]:
                if wl == "unweighted" and k != "Kappa":
                    if k == "Accuracy":
                        lo, hi = wilson(m["TP"] + m["TN"], len(d))
                    else:
                        lo, hi = wilson(m[k] * den[k], den[k]) if den[k] else (np.nan, np.nan)
                else:
                    lo, hi = q.loc[.025, k], q.loc[.975, k]
                rows.append([truth, frame, wl, k, m[k], lo, hi])
            rows.append([truth, frame, wl, "TP/FP/FN/TN",
                         "/".join(f"{m[k]:.1f}" for k in ["TP", "FP", "FN", "TN"]), None, None])
            if wl == "unweighted":
                rows.append([truth, frame, wl, "n answered (Unsure excluded)",
                             float(len(d)), None, None])

S = pd.DataFrame(rows, columns=["Reviewer CHD =", "Frame", "Weighting", "Metric", "Estimate", "CI_low", "CI_high"])

# ---- by stratum (Yes|Partly, unweighted counts; weights shown) ----
by = []
STR_ORDER = ["A1 Clear Tier 1: CHD lesion term in title, tier 1 and RCDC CHD",
             "A2 Clear non-CHD cardiovascular (no CHD signal, CV title)",
             "A3 Clear non-CHD pediatric (no CHD signal, pediatric title)",
             "A4 Clear non-CHD: rest of NIH portfolio",
             "B1 Borderline: other Tier 1",
             "B2 Borderline: Tier 2",
             "B3 Borderline: non-CHD with CHD signal (RCDC-only, 1+ strong terms, developmental/excluded-condition title)"]
for s in STR_ORDER:
    g = D[D.stratum == s]
    a = g[g.rev.isin(["Yes", "Partly", "No"])]
    pp, rp = (a.tier != "Not CHD"), a.rev.isin(["Yes", "Partly"])
    tp, fp, fn, tn = int((pp & rp).sum()), int((pp & ~rp).sum()), int((~pp & rp).sum()), int((~pp & ~rp).sum())
    m = metr(pp, rp, np.ones(len(a))) if len(a) else {}
    by.append({
        "stratum": s, "N_frame": int(g.N_frame.iloc[0]), "n_sample": int(g.n_sample.iloc[0]),
        "n_answered": len(a), "n_Unsure": int((g.rev == "Unsure").sum()),
        "weight": float(g.weight.iloc[0]),
        "rev_Yes": int((g.rev == "Yes").sum()), "rev_Partly": int((g.rev == "Partly").sum()),
        "rev_No": int((g.rev == "No").sum()), "rev_Unsure": int((g.rev == "Unsure").sum()),
        "pipeline_CHD": int((g.tier != "Not CHD").sum()),
        "TP": tp, "FP": fp, "FN": fn, "TN": tn,
        "Sensitivity": m.get("Sensitivity", np.nan), "Specificity": m.get("Specificity", np.nan),
        "PPV": m.get("PPV", np.nan), "NPV": m.get("NPV", np.nan), "Kappa": m.get("Kappa", np.nan),
    })
BY = pd.DataFrame(by)

# ---- disagreements with reasons and standing-rule flags ----
REASONS = {
    "V4-115": (
        "False positive. Title and abstract are about identifying genomic variants underlying "
        "congenital heart defects (including AVSD) in Down syndrome, deployed as a CAVATICA "
        "informatics workflow. The adjudicated label is No; a prior v1 review of the same core "
        "was Yes. The title names congenital heart defects, so the Tier 1 label follows the "
        "standing inclusion rules. The No may reflect a methods/informatics reading rather than "
        "the CHD content of the aims."
    ),
    "V4-116": (
        "False positive on a borderline Tier 2 developmental-science grant (left-ventricle "
        "development and morphogenesis; heart-field progenitors). Two prior reviews of the same "
        "core (v2 and V3) were Yes; the V4 label is No. Standing rules do not exclude cardiac "
        "morphogenesis. The V4 No is a change of judgment on a basic heart-development grant, "
        "not a rule conflict."
    ),
    "V4-129": (
        "False positive on a borderline Tier 2 developmental-science grant. The title is about "
        "glycolysis and left-right curvature of the stomach; heterotaxy and birth defects are "
        "background. A prior v2 review of the same core was already No, so V4 agrees with the "
        "earlier reviewer and not with the pipeline. Standing rules are not in conflict. This "
        "is a candidate for tightening Tier 2 laterality terms so organ-specific non-cardiac "
        "laterality work is not treated as CHD."
    ),
    "V4-188": (
        "False positive on a borderline other-Tier-1 grant. The title is structural biology of "
        "polycystic kidney disease proteins. The abstract mentions that PKD1L1 mutations can "
        "cause heterotaxy, biliary atresia and congenital heart defects, which is enough for "
        "the current strong-term rule to fire, but CHD is not a study aim. A prior v1 review "
        "of the same core was already No. Standing rules are not in conflict. This is a "
        "candidate for requiring CHD as a study aim, not only as a mentioned associated phenotype."
    ),
}
FLAGS = {
    "V4-115": (
        "Conflicts with standing inclusion: the title names congenital heart defects (and the "
        "abstract names AVSD in Down syndrome), so a No label is at odds with treating "
        "clear CHD-titled grants as CHD. The pipeline label is the one consistent with the rules."
    ),
}
DIS = X[X.pp != X.rev.isin(["Yes", "Partly"])][
    ["Review ID", "FULL_PROJECT_NUM", "FY", "stratum", "tier", "t2_route", "rcdc",
     "title", "rev", "comments", "previously_reviewed", "prior_IDs", "prior_reviews", "USD"]
].copy()
DIS["error_type"] = np.where(DIS.tier != "Not CHD", "FP (pipeline CHD, reviewer No)",
                             "FN (pipeline not CHD, reviewer Yes|Partly)")
DIS["likely_reason"] = DIS["Review ID"].map(REASONS)
DIS["standing_rule_flag"] = DIS["Review ID"].map(lambda i: FLAGS.get(i, "No standing-rule conflict."))

# ---- Unsure rows (excluded from metrics) ----
UNS = D[D.rev == "Unsure"][
    ["Review ID", "FULL_PROJECT_NUM", "FY", "stratum", "tier", "t2_route", "title",
     "rev", "comments", "previously_reviewed", "prior_IDs", "prior_reviews"]
].copy()
UNS["note"] = [
    "Reviewer comment: not sure if mitral valve prolapse is acquired or congenital. "
    "Abstract frames MVP as a developmental valve-formation / cilia phenotype (DZIP1). "
    "Excluded from metrics.",
    "Reviewer comment: talks about a heart-development mechanism but not necessarily a "
    "congenital heart defect. Abstract links inverted cardiac looping to dextrocardia, "
    "septal defects and double-outlet right ventricle. Excluded from metrics.",
]

# ---- prior-label comparison ----
def parse_priors(s):
    if pd.isna(s) or str(s).strip() == "":
        return []
    out = []
    for p in str(s).split(";"):
        p = p.strip()
        if ":" not in p:
            continue
        left, lab = p.rsplit(":", 1)
        lab = lab.strip().capitalize()
        left = left.strip()
        m = re.search(r"(V\d+-\d+|V4-\d+|B-CHD-\d+|P-\d+)", left)
        pid = m.group(1) if m else ""
        src = left[:m.start()].strip() if m else left
        out.append((src, pid, lab))
    return out


P = D[D.prior_reviews.fillna("").astype(str).str.strip() != ""].copy()
P["prior_list"] = P.prior_reviews.map(parse_priors)
P["n_priors"] = P.prior_list.map(len)
P["prior_label_latest"] = P.prior_list.map(lambda xs: xs[-1][2] if xs else np.nan)
P["prior_all"] = P.prior_list.map(lambda xs: "; ".join(f"{a} {b}: {c}" for a, b, c in xs))
P2 = P[P.rev.isin(["Yes", "Partly", "No"])].copy()  # exclude Unsure from binary/exact-answered rates


def kap(a, b):
    a, b = np.asarray(a, bool), np.asarray(b, bool)
    po = (a == b).mean()
    pe = a.mean() * b.mean() + (1 - a.mean()) * (1 - b.mean())
    return po, (po - pe) / (1 - pe) if pe < 1 else np.nan


ag_rows = []
# all prior cases, exact including Unsure vs latest prior
ag_rows.append(["all prior cases vs latest prior label", "exact 4-level (incl. Unsure)",
                len(P), (P.rev == P.prior_label_latest).sum(),
                (P.rev == P.prior_label_latest).mean(), np.nan])
ag_rows.append(["prior cases excluding Unsure vs latest prior label", "exact 3-level (Yes/Partly/No)",
                len(P2), (P2.rev == P2.prior_label_latest).sum(),
                (P2.rev == P2.prior_label_latest).mean(), np.nan])
po, k = kap(P2.rev.isin(["Yes", "Partly"]), P2.prior_label_latest.isin(["Yes", "Partly"]))
ag_rows.append(["prior cases excluding Unsure vs latest prior label",
                "binary (Yes|Partly vs No)", len(P2),
                int((P2.rev.isin(["Yes", "Partly"]) == P2.prior_label_latest.isin(["Yes", "Partly"])).sum()),
                po, k])
# vs any prior (a grant agrees if it matches every listed prior label / binary)
def all_exact(r):
    return all(lab == r.rev for _, _, lab in r.prior_list)
def all_bin(r):
    now = r.rev in ("Yes", "Partly")
    return all((lab in ("Yes", "Partly")) == now for _, _, lab in r.prior_list)
ag_rows.append(["prior cases excluding Unsure vs every listed prior label", "exact 3-level",
                len(P2), sum(all_exact(r) for _, r in P2.iterrows()),
                np.mean([all_exact(r) for _, r in P2.iterrows()]), np.nan])
ag_rows.append(["prior cases excluding Unsure vs every listed prior label", "binary (Yes|Partly vs No)",
                len(P2), sum(all_bin(r) for _, r in P2.iterrows()),
                np.mean([all_bin(r) for _, r in P2.iterrows()]), np.nan])
AGP = pd.DataFrame(ag_rows, columns=["Comparison", "Agreement type", "n", "n_agree", "Rate", "Kappa"])
CT = pd.crosstab(P.prior_label_latest, P.rev, margins=True)
CT.index.name = "Prior label (latest)"
CT.columns.name = "V4 adjudicated"

flips = []
for _, r in P.iterrows():
    for src, pid, lab in r.prior_list:
        exact = r.rev == lab
        binary = (r.rev in ("Yes", "Partly")) == (lab in ("Yes", "Partly"))
        if r.rev == "Unsure":
            binary = False  # treat Unsure as not agreeing on the binary CHD call
        if exact and r.rev != "Unsure":
            continue
        if exact and r.rev == "Unsure":
            continue
        flips.append({
            "Review ID": r["Review ID"], "stratum": r.stratum, "title": r.title,
            "prior_source": src, "prior_ID": pid, "prior_label": lab,
            "V4_label": r.rev, "exact_match": exact,
            "binary_match_YesPartly_vs_No": (r.rev in ("Yes", "Partly")) == (lab in ("Yes", "Partly"))
            if r.rev != "Unsure" else np.nan,
            "change_type": (
                "Unsure (no CHD call in V4)" if r.rev == "Unsure"
                else "binary flip (CHD vs not CHD)" if (r.rev in ("Yes", "Partly")) != (lab in ("Yes", "Partly"))
                else "Yes <-> Partly (same binary CHD call)"
            ),
            "comments": r.comments,
        })
FL = pd.DataFrame(flips)

# ---- age (secondary; among grants both sides call CHD) ----
amap = {"Neither": "Not age-specific"}
A = X[X.pp & X.rev.isin(["Yes", "Partly"])].copy()
A["rev_age"] = A.age.replace(amap)
A_use = A[A.rev_age.isin(["Pediatric", "Adult", "Both", "Not age-specific"])]
ct = pd.crosstab(A_use.rev_age, A_use.age_v2)
po_a = (A_use.rev_age == A_use.age_v2).mean() if len(A_use) else np.nan
pe_a = sum((ct.sum(axis=1).get(k, 0) * ct.sum(axis=0).get(k, 0)) for k in ct.index) / max(len(A_use), 1) ** 2
AG = pd.DataFrame(
    [[len(A), int((A.age != A.age_raw).sum()), int((A.age == "Both (unclear)").sum()),
      len(A_use), po_a, (po_a - pe_a) / (1 - pe_a) if pe_a < 1 else np.nan]],
    columns=["n both-sides CHD", "n age capitalization normalized",
             "n age 'Both (unclear)' excluded from kappa", "n used for agreement",
             "Agreement", "Kappa"],
)

# ---- integrity (describe; do not emphasize personal identifiers) ----
init, dates = R["Reviewer code"], R["Review date (YYYY-MM-DD)"]
cm = D.comments
INT = pd.DataFrame([
    ["rows in CSV (excluding 2 trailing empty rows)", len(R)],
    ["unique Review IDs V4-001 to V4-200 all present, no extras or duplicates",
     set(R["Review ID"]) == {f"V4-{i:03d}" for i in range(1, 201)}],
    ["project numbers match answer key", True],
    ["CHD labels (Yes / Partly / No / Unsure)",
     ", ".join(f"{k} {v}" for k, v in D.rev.value_counts().items())],
    ["blank CHD labels", n_blank],
    ["Age labels (after capitalization fix of 2 lowercase values)",
     ", ".join(f"{k} {v}" for k, v in D.age.value_counts().items())],
    ["age values outside the dropdown (kept as written)",
     ", ".join(sorted(set(D.age) - {"Pediatric", "Adult", "Both", "Neither", "Unclear"})) or "none"],
    ["distinct reviewer codes",
     int(init.nunique(dropna=False))],
    ["review dates present / blank",
     f"{int(dates.notna().sum())} / {int(dates.isna().sum())}"],
    ["review date values (as written, MM/D/YYYY)",
     ", ".join(str(x) for x in dates.dropna().astype(str).value_counts().index)],
    ["comments non-blank", int((cm.str.strip() != "").sum())],
    ["comment length mean/sd/min/max",
     f"{cm.str.len().mean():.1f}/{cm.str.len().std():.1f}/{cm.str.len().min()}/{cm.str.len().max()}"],
    ["comments starting with ': ' (a pattern seen in an earlier AI-looking return)",
     int(cm.str.match(r"^\s*:\s").sum())],
], columns=["Check", "Value"])

NOTES = pd.DataFrame({
    "Notes": [
        "v2.3 pipeline vs adjudicated V4 review (200 grants). Seed for bootstrap = 1, 2,000 stratified draws.",
        "Primary truth: reviewer Yes or Partly = CHD. Yes-only is a sensitivity check. Two Unsure rows (both B2) are excluded from all metrics; original stratum weights are kept, so B2 contributes 8/10 of its frame weight.",
        "Unweighted figures describe this clear-case-heavy sample and will look better than portfolio performance. Use weighted figures for portfolio inference.",
        "A4 (rest of NIH portfolio) has weight 43,833.4 and 5 true negatives; it dominates weighted specificity, accuracy, NPV and kappa. Report weighted results both with and without A4.",
        "Standing rules (unchanged): exclude pediatric/neonatal pulmonary hypertension, congenital heart block and noncompaction unless another CHD lesion is also named; keep coarctation, PDA and SVAS; keep the F30/F31 anchor.",
        "No pipeline rule changes were made. See the Disagreements and Proposed_rule_changes sheets.",
        "Returned file copied to data/validation/v4_review_adjudicated.csv (Windows/Latin-1 encoding; two trailing empty rows dropped).",
        "Scoring command: python3 R/20_v4_score.py",
    ]
})

PROP = pd.DataFrame([
    ["Do not change",
     "V4-115 (A1, reviewer No; title names congenital heart defects in Down syndrome). "
     "The pipeline Tier 1 call follows the rules. The disagreement is with the adjudicated label, not the rule.",
     "None"],
    ["Do not change",
     "V4-116 (B2 developmental left-ventricle morphogenesis; reviewer No). "
     "Two prior reviews were Yes. Cardiac morphogenesis remains in scope for Tier 2.",
     "None"],
    ["Candidate tightening",
     "V4-129 (B2; glycolysis and stomach curvature / non-cardiac organ laterality). "
     "Pipeline Tier 2; reviewer No, matching a prior v2 No.",
     "Narrow Tier 2 laterality/heterotaxy terms so organ-specific laterality work that is not cardiac (here, stomach curvature) is not classified as CHD."],
    ["Candidate tightening",
     "V4-188 (B1; structural mechanisms of polycystic kidney disease proteins). "
     "Pipeline Tier 1 because the abstract mentions congenital heart defects as a PKD1L1 phenotype; reviewer No, matching a prior v1 No.",
     "Consider requiring CHD as a study aim, not only as a mentioned associated phenotype of a gene or protein under study."],
    ["No change indicated",
     "Standing-rule checks in this set: PDA (V4-029, V4-121) and coarctation (V4-183, abstract) were reviewer Yes / pipeline Tier 1. "
     "A pulmonary-hypertension title (V4-024) was reviewer No / pipeline not CHD. "
     "Noncompaction appears only as a phenotype in a grant whose title is congenital heart disease (V4-168), reviewer Yes. "
     "No heart-block or SVAS titles in the set.",
     "None"],
], columns=["Recommendation", "Evidence in this set", "Proposed change"])

with pd.ExcelWriter(OUTP, engine="openpyxl") as xw:
    NOTES.to_excel(xw, sheet_name="Notes", index=False)
    S.to_excel(xw, sheet_name="Summary", index=False)
    BY.to_excel(xw, sheet_name="By_stratum", index=False)
    DIS.to_excel(xw, sheet_name="Disagreements", index=False)
    UNS.to_excel(xw, sheet_name="Unsure", index=False)
    AGP.to_excel(xw, sheet_name="Prior_label_agreement", index=False)
    CT.to_excel(xw, sheet_name="Prior_label_crosstab")
    FL.to_excel(xw, sheet_name="Prior_label_changes", index=False)
    PROP.to_excel(xw, sheet_name="Proposed_rule_changes", index=False)
    AG.to_excel(xw, sheet_name="Age", index=False)
    ct.to_excel(xw, sheet_name="Age_confusion")
    INT.to_excel(xw, sheet_name="Integrity", index=False)

wb = load_workbook(OUTP)
wb.properties.creator = ""
wb.properties.lastModifiedBy = ""
wb.properties.title = "V4 review scoring (v2.3 pipeline)"
wb.save(OUTP)
pd.set_option("display.width", 280)
pd.set_option("display.max_colwidth", 80)
print(S.to_string())
print(BY.to_string())
print(AGP.to_string())
print("disagreements", list(DIS["Review ID"]))
print("flips", len(FL))
print("wrote", OUTP)
