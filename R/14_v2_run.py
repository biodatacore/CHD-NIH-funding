"""14_v2_run.py -- apply the v2 rules, build FY tables, in-sample rescore on the 833-grant sample,
and draw the fresh blinded 200-grant review set. Run from the project root after 13a_v2_pool.py.
Outputs: outputs/v2/chd_v2_funding.xlsx, outputs/v2/chd_v2_insample_rescore.xlsx,
         outputs/v2/chd_v2_review_BLIND.xlsx, outputs/v2/chd_v2_review_ANSWER_KEY.xlsx"""
import importlib.util, os, re, numpy as np, pandas as pd, pyreadr
import gzip
def _load_pickle(path):
    if os.path.exists(path):
        return pd.read_pickle(path)
    gz = path + ".gz" if not path.endswith(".gz") else path
    if os.path.exists(gz):
        with gzip.open(gz, "rb") as f:
            return pd.read_pickle(f)
    raise FileNotFoundError(path)

from openpyxl import load_workbook
from openpyxl.styles import Font, Alignment
from openpyxl.worksheet.datavalidation import DataValidation
spec = importlib.util.spec_from_file_location("rules", "R/13_v2_rules.py"); R = importlib.util.module_from_spec(spec); spec.loader.exec_module(R)
WHR = os.environ.get("CHD_WHR_WORK", "data/raw/whr_work"); OUT = os.environ.get("CHD_V2_OUT", "outputs/v2.4"); os.makedirs(OUT, exist_ok=True)
SEED = 20261103
D = R.classify(_load_pickle(os.environ.get("CHD_POOL", "data/work/v2_pool.pkl"))); D["kw"] = D.kw.astype(bool); D["rcdc"] = D.rcdc.astype(bool)
# de-identify titles used in any output (eg "Diversity Supplement - Firstname Lastname")
D["title"] = D.title.fillna("").str.replace(r"(?i)\b(supplement|fellowship|award|scholar)\s*[-:\u2013]\s*[A-Z][a-z]+(?:\s+[A-Z]\.?)?(?:\s+[A-Z][a-z'\-]+)+\s*$", lambda m: m.group(1) + " - [NAME]", regex=True)
D.drop(columns=["text"]).to_pickle(os.environ.get("CHD_V2_CLASSIFIED", "data/work/v2.4_classified.pkl"))
# ---------------- FY tables
M = lambda m: D[m].groupby("FY").USD.sum() / 1e6
KW1 = D.kw_v1 if "kw_v1" in D else D.kw
Y = pd.DataFrame({"old_keyword_M": M(KW1), "tier1_M": M(D.tier1), "tier2_M": M(D.tier2), "combined_M": M(D.chd_v2),
                  "RCDC_M": M(D.rcdc & D.FY.between(2016, 2025))}).reindex(range(2013, 2027)).fillna(0)
Y.loc[~Y.index.isin(range(2016, 2026)), "RCDC_M"] = np.nan
N = lambda m: D[m].groupby("FY").size()
Y["tier1_n"], Y["tier2_n"], Y["combined_n"], Y["old_n"] = N(D.tier1), N(D.tier2), N(D.chd_v2), N(KW1)
Y["combined_vs_old_pct"] = 100 * (Y.combined_M / Y.old_keyword_M - 1)
Y["combined_pct_of_RCDC"] = 100 * Y.combined_M / Y.RCDC_M
Y.index.name = "FY"
old_age = D[KW1].assign(a=D.age.astype(str).replace({"Basic/non-age-specific": "Not age-specific", "Unclear": "Unclear (v1 only)"}))
AGE_OLD = old_age.groupby(["FY", "a"]).USD.sum().unstack().fillna(0) / 1e6
AGE_NEW = D[D.chd_v2].groupby(["FY", "age_v2"]).USD.sum().unstack().fillna(0) / 1e6
AGE_T1 = D[D.tier1].groupby(["FY", "age_v2"]).USD.sum().unstack().fillna(0) / 1e6
def share(t): return (100 * t.div(t.sum(1), axis=0)).round(1)
tot = lambda t: (100 * t.sum() / t.sum().sum()).round(1)
AGE_SUM = pd.DataFrame({"v1 keyword (5-level), % of $ FY2013-2026": tot(AGE_OLD), "v2 tier 1, %": tot(AGE_T1), "v2 combined, %": tot(AGE_NEW)})
ROUTES = D[D.tier2].groupby(["t2_route"]).agg(project_years=("USD", "size"), USD_M=("USD", lambda x: x.sum() / 1e6))
DROPS = D[D.kw & ~D.tier1].groupby("t1_drop").agg(project_years=("USD", "size"), USD_M=("USD", lambda x: x.sum() / 1e6))
with pd.ExcelWriter(f"{OUT}/chd_v2_funding.xlsx") as xw:
    Y.round(2).to_excel(xw, sheet_name="Yearly"); AGE_SUM.to_excel(xw, sheet_name="Age_summary")
    AGE_NEW.round(2).to_excel(xw, sheet_name="Age_USD_M_combined"); share(AGE_NEW).to_excel(xw, sheet_name="Age_pct_combined")
    AGE_T1.round(2).to_excel(xw, sheet_name="Age_USD_M_tier1"); AGE_OLD.round(2).to_excel(xw, sheet_name="Age_USD_M_v1")
    ROUTES.round(2).to_excel(xw, sheet_name="Tier2_routes"); DROPS.round(2).to_excel(xw, sheet_name="Tier1_drops")
    D[D.chd_v2 | D.kw][["FY", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "IC", "ACT", "USD", "title", "rcdc", "kw", "tier", "t1_drop", "t2_route", "age", "age_v2"]].to_excel(xw, sheet_name="Projects", index=False)
# ---------------- in-sample rescore (833)
key = pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name="Key_CHD")
ret = pd.read_excel("outputs/reviewer_returned.xlsx", sheet_name="CHD_review")
CC, CA = "CHD focus (Yes / Partly / No / Unsure)", "Age population (Pediatric / Adult / Both / Neither / Unclear)"
S = key[["Review ID", "Project number", "Fiscal year", "Stratum", "Pipeline_keyword_CHD"]].merge(ret[["Review ID", CC, CA]], on="Review ID")
S["R1"] = S[CC].astype(str).str.strip().str.capitalize()
rc = pd.read_excel("outputs/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx", sheet_name="Map_CHD")
rb = pd.read_excel(os.environ.get("CHD_RECHECK_RETURNED", "data/validation/priority_recheck_returned.xlsx"), sheet_name="CHD_review")
rc = rc.merge(rb[["Review ID", CC, CA]], left_on="Priority_ID", right_on="Review ID", suffixes=("", "_r2"))
rc["R2"] = rc[CC].astype(str).str.strip().str.capitalize()
o12 = rc[rc.Internal_Tier.isin([1, 2]) & (rc.R2 != "Unsure")].set_index("Round1_Review_ID").R2
S["Final"] = S["Review ID"].map(o12).fillna(S.R1)
_ov = os.environ.get("CHD_REF_OVERRIDES")
if _ov:  # reference-label overrides for the v1 833 review (eg v2.3 expert exclusions)
    _o = pd.read_excel(_ov, sheet_name="Overrides"); _o = _o[_o.review.str.startswith("v1")].set_index("Review ID")["new label"]
    S["Final"] = S["Review ID"].map(_o).fillna(S["Final"])
oa = rc[rc.Internal_Tier == 3].set_index("Round1_Review_ID")[CA]
S["Final_age"] = S["Review ID"].map(oa).fillna(S[CA])
S = S.merge(D.assign(kw=KW1)[["FY", "FULL_PROJECT_NUM", "kw", "tier1", "tier2", "chd_v2", "tier", "age_v2", "title"]], left_on=["Fiscal year", "Project number"], right_on=["FY", "FULL_PROJECT_NUM"], how="left", suffixes=("_v1key", ""))
for c in ["kw", "tier1", "tier2", "chd_v2"]: S[c] = S[c].fillna(False).astype(bool)
SIZES = {"Keyword CHD (all unique cores)": 690, "RCDC only (not keyword)": 459, "Near-miss negative (1-2 strong terms)": 429}
ns = S.Stratum.value_counts(); S["w"] = S.Stratum.map(lambda s: SIZES[s] / ns[s])
def metr(pp, rp, w):
    pp, rp, w = np.asarray(pp, bool), np.asarray(rp, bool), np.asarray(w, float)
    tp, fp, fn, tn = w[pp & rp].sum(), w[pp & ~rp].sum(), w[~pp & rp].sum(), w[~pp & ~rp].sum(); n = tp + fp + fn + tn
    po = (tp + tn) / n; pe = ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / n ** 2
    f = lambda a, b: a / (a + b) if a + b > 0 else np.nan
    return dict(Sensitivity=f(tp, fn), Specificity=f(tn, fp), PPV=f(tp, fp), NPV=f(tn, fn), Accuracy=po, Kappa=(po - pe) / (1 - pe), TP=tp, FP=fp, FN=fn, TN=tn)
def boot(pp, rp, w, st, B=2000):
    g = [np.where(st == s)[0] for s in pd.unique(st)]; r = np.random.default_rng(1); out = []
    for _ in range(B):
        b = np.concatenate([r.choice(x, len(x)) for x in g]); out.append(metr(pp[b], rp[b], w[b]))
    return pd.DataFrame(out).quantile([.025, .975])
rows = []
st = S.Stratum.values
for truth, tf in [("Yes|Partly", lambda x: x.isin(["Yes", "Partly"])), ("Yes only", lambda x: x == "Yes")]:
    rp = tf(S.Final).values
    for lab, pp in [("v1 keyword", S.kw.values), ("v2 tier 1", S.tier1.values), ("v2 combined (tier 1 + 2)", S.chd_v2.values)]:
        for wl, w in [("unweighted", np.ones(len(S))), ("weighted", S.w.values)]:
            m = metr(pp, rp, w); q = boot(pp, rp, w, st)
            for k in ["Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa"]:
                rows.append(["IN-SAMPLE (development data)", truth, lab, wl, k, m[k], q.loc[.025, k], q.loc[.975, k]])
            rows.append(["IN-SAMPLE (development data)", truth, lab, wl, "TP/FP/FN/TN", "/".join(f"{m[k]:.0f}" for k in ["TP", "FP", "FN", "TN"]), None, None])
IS = pd.DataFrame(rows, columns=["Label", "Reviewer CHD =", "Definition", "Weighting", "Metric", "Estimate", "CI_low", "CI_high"])
amap = {"Neither": "Not age-specific", "Neither / not age-specific": "Not age-specific"}
A = S[S.chd_v2 & S.Final.isin(["Yes", "Partly"])].copy(); A["rev_age"] = A.Final_age.replace(amap)
A = A[A.rev_age.isin(["Pediatric", "Adult", "Both", "Not age-specific"])]
po = (A.rev_age == A.age_v2).mean(); ct = pd.crosstab(A.rev_age, A.age_v2)
pe = sum(ct.sum(1).get(k, 0) * ct.sum(0).get(k, 0) for k in ct.index) / len(A) ** 2
AG = pd.DataFrame([["IN-SAMPLE age (v2 4-level) vs reviewer, CHD-positive rows with a definite reviewer age", len(A), po, (po - pe) / (1 - pe)]], columns=["Item", "n", "Agreement", "Kappa"])
DIS = S[(S.chd_v2 != S.Final.isin(["Yes", "Partly"]))][["Review ID", "Project number", "Fiscal year", "Stratum", "title", "tier", "Final"]]
with pd.ExcelWriter(f"{OUT}/chd_v2_insample_rescore.xlsx") as xw:
    pd.DataFrame({"NOTE": ["IN-SAMPLE CHECK ONLY. The 833-grant sample (and its 36 confirmed misses / 9 confirmed false positives) was used to develop the v2 rules, so these metrics are optimistic. Use the fresh 200-grant set for out-of-sample validation.",
                           "Weighted = inverse-probability weights to the v1 sampling frame (keyword 690/689, RCDC-only 459/95, near-miss 429/49); 95% CI = stratified bootstrap (2,000 draws). The frame excludes NIH grants with no CHD signal."]}).to_excel(xw, sheet_name="README", index=False)
    IS.to_excel(xw, sheet_name="Metrics", index=False); AG.to_excel(xw, sheet_name="Age", index=False); ct.to_excel(xw, sheet_name="Age_confusion")
    DIS.to_excel(xw, sheet_name="Disagreements", index=False)
if os.environ.get("DRAW_SAMPLE", "0") != "1":   # v2.1: the v2 fresh set is kept; new sets are drawn by R/17_v3_sample.py
    print(Y.round(1).to_string()); print(AGE_SUM.to_string()); print(ROUTES); print(DROPS); print(AG.to_string()); raise SystemExit
# ---------------- fresh 200-grant stratified sample (v2 only; run with DRAW_SAMPLE=1 CHD_V2_OUT=outputs/v2)
prior = set()
for sh in ["Key_CHD", "Key_Age", "Key_CVD"]:
    prior |= set(pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name=sh)["Project number"])
pj = pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name="Prior_judgments"); prior |= set(pj.project_number)
s_old = pyreadr.read_r("data/work/sample.rds")[None]; prior |= set(s_old.FULL_PROJECT_NUM)
f2c = dict(zip(D.FULL_PROJECT_NUM, D.CORE_PROJECT_NUM))
prior_cores = {f2c.get(p, p) for p in prior}
D["near_bound"] = ~D.chd_v2 & (D.s_str.between(1, 2) | (R.cnt(D.title.fillna("").str.lower() + " ", R.DEV) > 0))
D["stratum"] = np.select([D.tier1, D.tier2 & (D.t2_route == "developmental science"), D.tier2, D.kw & ~D.tier1,
                          ~D.chd_v2 & D.rcdc, D.near_bound], ["S1 Tier 1 CHD-focused", "S2 Tier 2 developmental science",
                          "S3 Tier 2 pediatric device / trainee", "S4 Dropped from v1 keyword (platform/center/fix)",
                          "S5 Boundary negative: RCDC CHD, not v2", "S6 Boundary negative: 1-2 strong terms or dev title, not v2"], "S7 Other CHD-signal negative")
# NOTE: every v1 keyword-positive core (hence every tier-1 core and every core dropped from v1) was already
# reviewed in the v1 833-grant sample, so strata S1/S4 have no fresh frame; their 60 slots go to tier 2 and boundary negatives.
ALLOC = {"S1 Tier 1 CHD-focused": 50, "S4 Dropped from v1 keyword (platform/center/fix)": 10,
         "S2 Tier 2 developmental science": 45, "S3 Tier 2 pediatric device / trainee": 30,
         "S5 Boundary negative: RCDC CHD, not v2": 45, "S6 Boundary negative: 1-2 strong terms or dev title, not v2": 45,
         "S7 Other CHD-signal negative": 35}
fr = D.sort_values("FY", ascending=False)
RT = []
for fy in range(2013, 2027):
    r = pyreadr.read_r(f"{WHR}/rows/rows_{fy}.rds")[None]
    r = r[r.FULL_PROJECT_NUM.isin(fr.FULL_PROJECT_NUM[fr.FY == fy])].copy(); r["par"] = r.SUBPROJECT_ID.isna()
    r = r.sort_values(["FULL_PROJECT_NUM", "par"], ascending=[True, False]).drop_duplicates("FULL_PROJECT_NUM"); r["FY"] = fy
    RT.append(r[["FY", "FULL_PROJECT_NUM", "APPLICATION_ID", "ABSTRACT_TEXT", "PHR"]])
RT = pd.concat(RT); fr = fr.merge(RT, on=["FY", "FULL_PROJECT_NUM"], how="left")
fr = fr[fr.ABSTRACT_TEXT.fillna("").str.len() >= 40]
fr = fr.drop_duplicates("CORE_PROJECT_NUM")   # one project-year per core: most recent FY with an abstract
frame = fr[~fr.CORE_PROJECT_NUM.isin(prior_cores)]
picks = []
for s, n in ALLOC.items():
    g = frame[frame.stratum == s]; k = min(n, len(g)); picks.append(g.sample(k, random_state=SEED).assign(N_frame=len(g), n_sample=k))
SMP = pd.concat(picks); SMP["weight"] = SMP.N_frame / SMP.n_sample
SMP = SMP.sample(frac=1, random_state=SEED + 1).reset_index(drop=True); SMP["Review ID"] = [f"V2-{i+1:03d}" for i in range(len(SMP))]
ILL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")
def clean(v, n):
    v = "" if pd.isna(v) else ILL.sub("", str(v))
    v = re.sub(r"(?i)\b(dr\.?|prof(?:essor)?\.?|mrs?\.?|ms\.)\s+[A-Z][a-z]+(?:\s+[A-Z]\.?)*\s+[A-Z][a-z]+(-[A-Z][a-z]+)?", "[NAME]", v)
    v = re.sub(r"(?i)\b(candidate|principal investigator|pi|mentor|co-?mentor|co-?investigator|trainee|sponsor)\s*[:：]\s*[^\n\.]{0,80}", r"\1: [NAME]", v)
    v = re.sub(r"\b[A-Z][a-z]+(?:\s+[A-Z]\.)?\s+[A-Z][a-z]+,\s*(MD|PhD|MD/PhD|DO|DVM|RN|NP)\b", r"[NAME], \1", v)
    v = re.sub(r"\bDrs?\.?\s+[A-Z][A-Za-z'\-]+(?:\s+[A-Z][A-Za-z'\-]+)?", "[NAME]", v)
    # names listed after mentoring / team words (trainee and career awards)
    NM = r"(?:\[NAME\]|[A-Z]\.|[A-Z][a-z]+[A-Za-z'\-]*)"
    v = re.sub(r"(?i:(mentorship|guidance|supervision|direction|leadership|mentors?|co-?mentors?|sponsors?|co-?sponsors?|advisors?|led by|team of|consultants?|collaborators?|collaborat[a-z]* with|working with|work with|together with|labs? of|laborator(?:y|ies) of))"
               r"((?:\s+(?i:of|by|are|is|include|including|from|with|drs?\.?))*[\s,:(]+)" + NM + r"(?:(?:\s*,\s*|\s+|\s*,?\s+(?:and|&)\s+)" + NM + r")*",
               lambda m: m.group(1) + m.group(2) + "[NAME]", v)
    v = re.sub(r"(\[NAME\])(?:(?:\s*,\s*|\s*,?\s+(?:and|&)\s+)(?:\[NAME\]|[A-Z][a-z]+[A-Za-z'\-]*))+", "[NAME]", v)
    return v[:n]
aid = SMP.APPLICATION_ID.astype(float).astype("Int64").astype(str)
B = pd.DataFrame({"Review ID": SMP["Review ID"], "Project number": SMP.FULL_PROJECT_NUM, "Fiscal year": SMP.FY, "IC": SMP.IC, "Activity": SMP.ACT,
                  "APPLICATION_ID": aid, "RePORTER": "https://reporter.nih.gov/project-details/" + aid,
                  "Title": SMP.title.map(lambda x: clean(x, 500)), "Abstract / project summary": SMP.ABSTRACT_TEXT.map(lambda x: clean(x, 8000)),
                  "Public health narrative": SMP.PHR.map(lambda x: clean(x, 4000) or "(no public health narrative in source record)"),
                  CC: "", CA: "", "Reviewer code": "", "Review date (YYYY-MM-DD)": "", "Comments": ""})
readme = ["BLIND MANUAL REVIEW (v2 fresh set) — NIH congenital heart disease (CHD) research grants", "",
 "1. Work alone. Judge only from Title, Abstract, Public health narrative and the RePORTER link.",
 "2. Do not look at earlier review files, answer keys or scoring files.",
 "3. Ignore residual person names or [NAME] placeholders; do not copy names into Comments.",
 "4. Use the dropdowns; add initials and date on every row you complete. Rows are in random order.", "",
 "CHD focus:", " - Yes = primary/substantial focus on CHD or a named structural lesion/palliation (Fontan, HLHS, ToF, TGA, septal defects, ACHD, etc.),",
 "   including developmental-biology work whose stated aim is how congenital heart defects arise.",
 " - Partly = CHD is one aim or a clear motivation only (or mixed congenital + acquired).",
 " - No = not CHD (acquired disease, coronary disease, channelopathy/arrhythmia without a congenital lesion, platforms that only mention CHD).",
 " - Unsure = cannot decide from the text.", "",
 "Age population: Pediatric (<18, incl. fetal) / Adult (18+, incl. ACHD) / Both (lifespan, transition, or both) /",
 " Neither = not age-specific (basic science, animal, iPSC, methods with no human age target) / Unclear.", "",
 f"This file has {len(B)} rows (~1-2 minutes each)."]
blind = f"{OUT}/chd_v2_review_BLIND.xlsx"
with pd.ExcelWriter(blind) as xw:
    pd.DataFrame({readme[0]: readme[1:]}).to_excel(xw, sheet_name="READ ME FIRST", index=False); B.to_excel(xw, sheet_name="CHD_review", index=False)
wb = load_workbook(blind)
for sh in wb.worksheets:
    for row in sh.iter_rows():
        for c in row: c.font = Font(name="Arial", size=11, bold=(c.row == 1)); c.alignment = Alignment(wrap_text=True, vertical="top")
ws = wb["CHD_review"]
for col, wdt in zip("ABCDEFGHIJKLMNO", [10, 20, 9, 6, 8, 12, 30, 40, 80, 50, 18, 22, 10, 14, 30]): ws.column_dimensions[col].width = wdt
for r in range(2, ws.max_row + 1): ws[f"G{r}"].hyperlink = ws[f"G{r}"].value; ws[f"G{r}"].font = Font(name="Arial", size=11, color="0563C1", underline="single")
for colL, opts in [("K", "Yes,Partly,No,Unsure"), ("L", "Pediatric,Adult,Both,Neither,Unclear")]:
    dv = DataValidation(type="list", formula1=f'"{opts}"', allow_blank=True); ws.add_data_validation(dv); dv.add(f"{colL}2:{colL}{ws.max_row}")
ws.freeze_panes = "B2"; wb["READ ME FIRST"].column_dimensions["A"].width = 130
wb.properties.creator = ""; wb.properties.lastModifiedBy = ""; wb.properties.title = ""; wb.save(blind)
KEY = SMP[["Review ID", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "FY", "IC", "ACT", "APPLICATION_ID", "USD", "stratum", "N_frame", "n_sample", "weight",
           "tier", "t2_route", "t1_drop", "kw", "rcdc", "age_v2", "age", "title"]].rename(columns={"age": "age_v1"})
W = SMP.groupby("stratum").agg(N_frame=("N_frame", "first"), n_sample=("n_sample", "first"), weight=("weight", "first"))
with pd.ExcelWriter(f"{OUT}/chd_v2_review_ANSWER_KEY.xlsx") as xw:
    pd.DataFrame({"ANSWER KEY — do not give to reviewers": [f"Seed {SEED}. Frame = unique core projects in the CHD-signal pool with an abstract, NOT in any prior sample (v1 833-grant review, earlier 147-grant check, priority recheck); {len(prior_cores)} prior cores excluded.",
        "One representative project-year per core (most recent FY with an abstract). Weight = N_frame / n_sample within stratum.",
        "Score with R/15_v2_score_review.py after the reviewer returns the BLIND workbook."]}).to_excel(xw, sheet_name="Notes", index=False)
    KEY.to_excel(xw, sheet_name="Key", index=False); W.to_excel(xw, sheet_name="Strata_weights")
assert not set(B.columns) & {"tier", "stratum", "weight", "kw", "rcdc"}
assert not B["Project number"].map(lambda p: f2c.get(p, p)).isin(prior_cores).any()
pd.set_option("display.width", 250); pd.set_option("display.max_columns", 20)
print(Y.round(1).to_string()); print(AGE_SUM.to_string()); print(ROUTES); print(DROPS)
#print(IS[(IS.Metric.isin(["Sensitivity", "Specificity", "PPV", "NPV", "Kappa", "TP/FP/FN/TN"]))].to_string())
print(AG.to_string()); print(W); print(len(B), "prior cores", len(prior_cores))
