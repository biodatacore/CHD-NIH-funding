"""18_v3_extras.py -- V3 review extras: weighted metrics without the no-signal stratum, agreement with earlier
reviewer labels for previously reviewed grants, integrity flags. Appends sheets to outputs/v2.1/chd_v3_review_scoring.xlsx."""
import numpy as np, pandas as pd, pyreadr
import os
CC = "CHD focus (Yes / Partly / No / Unsure)"; OUTP = os.environ.get("CHD_SCORE_OUT", "outputs/v2.1/chd_v3_review_scoring.xlsx")
K = pd.read_excel("outputs/v2.1/chd_v3_review_ANSWER_KEY.xlsx", sheet_name="Key"); R = pd.read_excel(os.environ.get("CHD_V3_RETURNED", "data/validation/v3_review_returned.xlsx"), sheet_name="CHD_review")
if os.environ.get("CHD_RELABEL"):  # use the rule version being scored (labels from the classified pickle)
    _L = pd.read_pickle(os.environ["CHD_RELABEL"])[["FY", "FULL_PROJECT_NUM", "tier"]]
    K = K.drop(columns=["tier"]).merge(_L, on=["FY", "FULL_PROJECT_NUM"], how="left"); K["tier"] = K.tier.fillna("Not CHD")
X = K.merge(R[["Review ID", CC, "Comments"]], on="Review ID"); X["rev"] = X[CC].astype(str).str.strip().str.capitalize()
X = X[X.rev.isin(["Yes", "Partly", "No"])]; X["pp"] = X.tier != "Not CHD"
def metr(pp, rp, w):
    tp, fp, fn, tn = w[pp & rp].sum(), w[pp & ~rp].sum(), w[~pp & rp].sum(), w[~pp & ~rp].sum(); n = tp + fp + fn + tn
    po = (tp + tn) / n; pe = ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / n ** 2
    f = lambda a, b: a / (a + b) if a + b else np.nan
    return dict(Sensitivity=f(tp, fn), Specificity=f(tn, fp), PPV=f(tp, fp), NPV=f(tn, fn), Kappa=(po - pe) / (1 - pe), TP=tp, FP=fp, FN=fn, TN=tn)
rows = []
for lab, d in [("all 7 strata (portfolio)", X), ("without V7 no-signal stratum (CHD-signal frame)", X[~X.stratum.str.startswith("V7")])]:
    for truth, tf in [("Yes|Partly", lambda s: s.isin(["Yes", "Partly"])), ("Yes only", lambda s: s == "Yes")]:
        pp, rp, w, st = d.pp.values, tf(d.rev).values, d.weight.values, d.stratum.values
        m = metr(pp, rp, w); g = [np.where(st == s)[0] for s in pd.unique(st)]; r = np.random.default_rng(1)
        q = pd.DataFrame([metr(pp[b], rp[b], w[b]) for b in (np.concatenate([r.choice(x, len(x)) for x in g]) for _ in range(2000))]).quantile([.025, .975])
        for k in ["Sensitivity", "Specificity", "PPV", "NPV", "Kappa"]: rows.append([lab, truth, k, m[k], q.loc[.025, k], q.loc[.975, k]])
WS = pd.DataFrame(rows, columns=["Frame", "Reviewer CHD =", "Metric", "Weighted estimate", "CI_low", "CI_high"])
# earlier labels by core project
key = pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name="Key_CHD"); r1 = pd.read_excel("outputs/reviewer_returned.xlsx", sheet_name="CHD_review")
rc = pd.read_excel("outputs/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx", sheet_name="Map_CHD"); rb = pd.read_excel("data/validation/priority_recheck_returned.xlsx", sheet_name="CHD_review")
rc = rc.merge(rb[["Review ID", CC]], left_on="Priority_ID", right_on="Review ID", suffixes=("", "_r2"))
o = rc[rc.Internal_Tier.isin([1, 2]) & (rc[CC] != "Unsure")].set_index("Round1_Review_ID")[CC]
S = key[["Review ID", "Project number"]].merge(r1[["Review ID", CC]], on="Review ID"); S["prior"] = S["Review ID"].map(o).fillna(S[CC]).str.strip().str.capitalize()
D = pd.read_pickle(os.environ.get("CHD_RELABEL", "data/work/v2.1_classified.pkl")); f2c = dict(zip(D.FULL_PROJECT_NUM, D.CORE_PROJECT_NUM))
S["core"] = S["Project number"].map(lambda p: f2c.get(p, p)); S["src"] = "v1 review (adjudicated)"
v2k = pd.read_excel("outputs/v2/chd_v2_review_ANSWER_KEY.xlsx", sheet_name="Key"); v2r = pd.read_excel("data/validation/v2_review_returned.xlsx", sheet_name="CHD_review")
V = v2k[["Review ID", "CORE_PROJECT_NUM"]].merge(v2r[["Review ID", CC]], on="Review ID").rename(columns={"CORE_PROJECT_NUM": "core", CC: "prior"}); V["src"] = "v2 fresh set"
P = pd.concat([S[["core", "prior", "src"]], V[["core", "prior", "src"]]]).drop_duplicates("core")
A = K.merge(R[["Review ID", CC]], on="Review ID").merge(P, left_on="CORE_PROJECT_NUM", right_on="core", how="inner")
A["now"] = A[CC].str.strip().str.capitalize(); A["pos_now"] = A.now.isin(["Yes", "Partly"]); A["pos_prior"] = A.prior.isin(["Yes", "Partly"])
def kap(a, b):
    po = (a == b).mean(); pe = a.mean() * b.mean() + (1 - a.mean()) * (1 - b.mean()); return po, (po - pe) / (1 - pe)
AG = []
for src, g in [("all", A)] + list(A.groupby("src")):
    g2 = g[g.now != "Unsure"]; po, k = kap(g2.pos_now, g2.pos_prior)
    AG.append([src, len(g), len(g2), (g2.now == g2.prior).mean(), po, k])
AG = pd.DataFrame(AG, columns=["Earlier review", "n matched", "n (excl Unsure)", "Exact 3-level agreement", "Binary agreement (Yes|Partly vs No)", "Binary kappa"])
CT = pd.crosstab([A.src, A.prior], A.now)
cm = R.Comments.fillna("").astype(str)
INT = pd.DataFrame([["rows", len(R)], ["IDs match key", set(R["Review ID"]) == set(K["Review ID"])], ["blank CHD / age", int(R[CC].isna().sum())],
    ["Unsure", int((R[CC] == "Unsure").sum())], ["n distinct reviewer codes", int(R[[c for c in R.columns if c.lower().startswith("reviewer") and "comment" not in c.lower() and "date" not in c.lower()][0]].nunique()) if any(c.lower().startswith("reviewer") and "comment" not in c.lower() and "date" not in c.lower() for c in R.columns) else 0], ["dates", ",".join(R["Review date (YYYY-MM-DD)"].astype(str).unique())],
    ["comments non-blank", int((cm != "").sum())], ["comment length mean/sd/min/max", f"{cm.str.len().mean():.0f}/{cm.str.len().std():.0f}/{cm.str.len().min()}/{cm.str.len().max()}"],
    ["comments starting ': '", int(cm.str.match(r"^\s*:\s").sum())]], columns=["Check", "Value"])
with pd.ExcelWriter(OUTP, mode="a", engine="openpyxl", if_sheet_exists="replace") as xw:
    INT.to_excel(xw, sheet_name="Integrity", index=False); WS.to_excel(xw, sheet_name="Weighted_with_without_V7", index=False)
    AG.to_excel(xw, sheet_name="Prior_label_agreement", index=False); CT.to_excel(xw, sheet_name="Prior_label_crosstab")
    A[A.pos_now != A.pos_prior][["Review ID", "FULL_PROJECT_NUM", "stratum", "tier", "src", "prior", "now", "title"]].to_excel(xw, sheet_name="Prior_label_changes", index=False)
pd.set_option("display.width", 250); print(WS.to_string()); print(AG.to_string()); print(CT)
