"""19_v4_sample.py -- draw the V4 200-grant blinded review set under v2.3 rules, weighted toward CLEAR cases
(clear tier-1 CHD lesion grants; clear non-CHD cardiovascular / pediatric grants) with a small borderline share; portfolio weights kept.
Frame = all NIH core projects FY2013-2026 (one representative project-year per core: most recent FY with an abstract).
Previously reviewed grants may be included (user-approved); order is shuffled and IDs (V4-###) do not encode prior IDs.
Outputs: outputs/v2.3/chd_v4_review_BLIND.xlsx, outputs/v2.1/chd_v3_review_ANSWER_KEY.xlsx
Then run R/14b_v2_scrub_names.py with CHD_BLIND=outputs/v2.3/chd_v4_review_BLIND.xlsx."""
import os, re, numpy as np, pandas as pd, pyreadr, importlib.util
from openpyxl import load_workbook
from openpyxl.styles import Font, Alignment
from openpyxl.worksheet.datavalidation import DataValidation
spec = importlib.util.spec_from_file_location("rules", "R/13_v2_rules.py"); R = importlib.util.module_from_spec(spec); spec.loader.exec_module(R)
WHR = os.environ.get("CHD_WHR_WORK", "data/raw/whr_work"); OUT = "outputs/v2.3"; SEED = 20261105
D = pd.read_pickle("data/work/v2.3_classified.pkl")
pool_txt = pd.read_pickle("data/work/v2_pool.pkl")[["FY", "FULL_PROJECT_NUM", "title"]]
D["dev_title"] = R.cnt(D.title.fillna("").str.lower(), R.DEV) > 0
D["in_pool"] = True
# no-signal portfolio stratum: every other NIH project-year (from C.rds)
C = pyreadr.read_r("data/work/C.rds")[None][["FY", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "IC", "ACT", "USD", "title"]]
C = C[~C.FULL_PROJECT_NUM.isin(D.FULL_PROJECT_NUM) | ~C.set_index(["FY", "FULL_PROJECT_NUM"]).index.isin(D.set_index(["FY", "FULL_PROJECT_NUM"]).index)]
C = C[~C.CORE_PROJECT_NUM.isin(D.CORE_PROJECT_NUM)].assign(stratum="V7 No CHD signal (rest of NIH portfolio)", tier="Not CHD", t2_route="", t1_drop="", age_v2="Not age-specific", rcdc=False, kw=False)
ALL = pd.concat([D, C], ignore_index=True)
# core-level unit: most recent project-year; stratum of that project-year
ALL = ALL.sort_values("FY", ascending=False).drop_duplicates("CORE_PROJECT_NUM")
tl = ALL.title.fillna("").str.lower(); s_str = ALL.s_str.fillna(0); rc = ALL.rcdc.fillna(False).astype(bool)
dev = ALL.dev_title.fillna(False).astype(bool); ex = ALL.excl_v23.fillna(False).astype(bool); t_str = ALL.t_str.fillna(0)
cv = tl.str.contains(r"(cardi|heart|coronary|myocard|vascular|vessel|atheroscl|arrhythm|atrial|aortic|hypertens|stroke|thromb|valve)"); ped = tl.str.contains(r"(pediatric|paediatric|child|infant|neonat|newborn|adolescen|youth|preterm|kids?\b)")
clean_neg = (ALL.tier == "Not CHD") & ~rc & (s_str == 0) & ~dev & ~ex & ~tl.str.contains(r"congenital|birth defect|cardiogen|heart (development|field)|neural crest|fetal")
ALL["stratum"] = np.select([ALL.tier1.fillna(False).astype(bool) & (t_str >= 1) & rc,
    ALL.tier1.fillna(False).astype(bool), ALL.tier2.fillna(False).astype(bool),
    (ALL.tier == "Not CHD") & ~clean_neg,
    clean_neg & cv, clean_neg & ped],
    ["A1 Clear Tier 1: CHD lesion term in title, tier 1 and RCDC CHD", "B1 Borderline: other Tier 1", "B2 Borderline: Tier 2",
     "B3 Borderline: non-CHD with CHD signal (RCDC-only, 1+ strong terms, developmental/excluded-condition title)",
     "A2 Clear non-CHD cardiovascular (no CHD signal, CV title)", "A3 Clear non-CHD pediatric (no CHD signal, pediatric title)"],
    "A4 Clear non-CHD: rest of NIH portfolio")
ALLOC = {"A1 Clear Tier 1: CHD lesion term in title, tier 1 and RCDC CHD": 85, "A2 Clear non-CHD cardiovascular (no CHD signal, CV title)": 45,
         "A3 Clear non-CHD pediatric (no CHD signal, pediatric title)": 35, "A4 Clear non-CHD: rest of NIH portfolio": 5,
         "B1 Borderline: other Tier 1": 10, "B2 Borderline: Tier 2": 10,
         "B3 Borderline: non-CHD with CHD signal (RCDC-only, 1+ strong terms, developmental/excluded-condition title)": 10}
rng = np.random.default_rng(SEED)
# oversample candidates then keep those with an abstract (checked per FY)
cand = pd.concat([g.sample(min(len(g), ALLOC[s] * 3), random_state=SEED) for s, g in ALL.groupby("stratum")])
RT = []
for fy in sorted(cand.FY.unique()):
    r = pyreadr.read_r(f"{WHR}/rows/rows_{fy}.rds")[None]
    r = r[r.FULL_PROJECT_NUM.isin(cand.FULL_PROJECT_NUM[cand.FY == fy])].copy(); r["par"] = r.SUBPROJECT_ID.isna()
    r = r.sort_values(["FULL_PROJECT_NUM", "par"], ascending=[True, False]).drop_duplicates("FULL_PROJECT_NUM"); r["FY"] = fy
    RT.append(r[["FY", "FULL_PROJECT_NUM", "APPLICATION_ID", "ABSTRACT_TEXT", "PHR"]])
cand = cand.merge(pd.concat(RT), on=["FY", "FULL_PROJECT_NUM"], how="left")
cand["has_abs"] = cand.ABSTRACT_TEXT.fillna("").str.len() >= 40
N = ALL.stratum.value_counts()
picks = []
for s, n in ALLOC.items():
    g = cand[(cand.stratum == s) & cand.has_abs].head(n)   # cand is already a random order within stratum
    picks.append(g.assign(N_frame=N[s], n_sample=len(g)))
SMP = pd.concat(picks); SMP["weight"] = SMP.N_frame / SMP.n_sample
# previously reviewed? (v1 833 review, earlier 147 check, priority recheck, v2 fresh 200)
prior = set()
for sh in ["Key_CHD", "Key_Age", "Key_CVD"]: prior |= set(pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name=sh)["Project number"])
prior |= set(pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name="Prior_judgments").project_number)
prior |= set(pyreadr.read_r("data/work/sample.rds")[None].FULL_PROJECT_NUM)
v2k = pd.read_excel("outputs/v2/chd_v2_review_ANSWER_KEY.xlsx", sheet_name="Key")
f2c = dict(zip(ALL.FULL_PROJECT_NUM, ALL.CORE_PROJECT_NUM)); f2c.update(dict(zip(D.FULL_PROJECT_NUM, D.CORE_PROJECT_NUM)))
prior_cores = {f2c.get(p, p) for p in prior}; v2_cores = set(v2k.CORE_PROJECT_NUM)
CCX = "CHD focus (Yes / Partly / No / Unsure)"
k1 = pd.read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet_name="Key_CHD")[["Review ID", "Project number"]]
r1 = pd.read_excel("outputs/reviewer_returned.xlsx", sheet_name="CHD_review")[["Review ID", CCX]]
rcm = pd.read_excel("outputs/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx", sheet_name="Map_CHD")
rbm = pd.read_excel("data/validation/priority_recheck_returned.xlsx", sheet_name="CHD_review")[["Review ID", CCX]]
rcm = rcm.merge(rbm, left_on="Priority_ID", right_on="Review ID", suffixes=("", "_r2")); rcm["R2"] = rcm[CCX].astype(str).str.strip().str.capitalize()
o12 = rcm[rcm.Internal_Tier.isin([1, 2]) & (rcm.R2 != "Unsure")].set_index("Round1_Review_ID").R2
k1 = k1.merge(r1, on="Review ID"); k1["lab"] = k1["Review ID"].map(o12).fillna(k1[CCX].astype(str).str.strip().str.capitalize())
ov = pd.read_excel("data/validation/v2.3_reference_overrides.xlsx", sheet_name="Overrides").set_index("Review ID")["new label"]
k1["lab"] = k1["Review ID"].map(ov).fillna(k1.lab); k1["core"] = k1["Project number"].map(lambda p: f2c.get(p, p))
k2 = v2k.merge(pd.read_excel("data/validation/v2_review_returned.xlsx", sheet_name="CHD_review")[["Review ID", CCX]], on="Review ID")
k3 = pd.read_excel("outputs/v2.1/chd_v3_review_ANSWER_KEY.xlsx", sheet_name="Key").merge(pd.read_excel("data/validation/v3_review_returned_v2.3ref.xlsx", sheet_name="CHD_review")[["Review ID", CCX]], on="Review ID")
PL = {}
for lab, df, cc in [("v1 833 review", k1, "core"), ("v2 fresh set", k2, "CORE_PROJECT_NUM"), ("V3 set", k3, "CORE_PROJECT_NUM")]:
    for _, r in df.iterrows(): PL.setdefault(r[cc], []).append((lab, r["Review ID"], str(r.get("lab", r.get(CCX))).strip().capitalize()))
SMP["prior_reviews"] = SMP.CORE_PROJECT_NUM.map(lambda c: "; ".join(f"{a} {b}: {l}" for a, b, l in PL.get(c, [])))
SMP["prior_IDs"] = SMP.CORE_PROJECT_NUM.map(lambda c: ", ".join(b for a, b, l in PL.get(c, [])))
prior_cores |= set(PL)
SMP["previously_reviewed"] = np.where(SMP.prior_reviews != "", "yes", np.where(SMP.CORE_PROJECT_NUM.isin(prior_cores), "yes (earlier check, no CHD label)", "no"))
SMP = SMP.sample(frac=1, random_state=SEED + 7).reset_index(drop=True); SMP["Review ID"] = [f"V4-{i+1:03d}" for i in range(len(SMP))]
ILL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]"); NM = r"(?:\[NAME\]|[A-Z]\.|[A-Z][a-z]+[A-Za-z'\-]*)"
def clean(v, n):
    v = "" if pd.isna(v) else ILL.sub("", str(v))
    v = re.sub(r"(?i)\b(dr\.?|prof(?:essor)?\.?|mrs?\.?|ms\.)\s+[A-Z][a-z]+(?:\s+[A-Z]\.?)*\s+[A-Z][a-z]+(-[A-Z][a-z]+)?", "[NAME]", v)
    v = re.sub(r"(?i)\b(candidate|principal investigator|pi|mentor|co-?mentor|co-?investigator|trainee|sponsor)\s*[:：]\s*[^\n\.]{0,80}", r"\1: [NAME]", v)
    v = re.sub(r"\b[A-Z][a-z]+(?:\s+[A-Z]\.)?\s+[A-Z][a-z]+,\s*(MD|PhD|MD/PhD|DO|DVM|RN|NP)\b", r"[NAME], \1", v)
    v = re.sub(r"\bDrs?\.?\s+[A-Z][A-Za-z'\-]+(?:\s+[A-Z][A-Za-z'\-]+)?", "[NAME]", v)
    v = re.sub(r"(?i:(mentorship|guidance|supervision|direction|leadership|mentors?|co-?mentors?|sponsors?|co-?sponsors?|advisors?|led by|team of|consultants?|collaborators?|collaborat[a-z]* with|working with|work with|together with|labs? of|laborator(?:y|ies) of))"
               r"((?:\s+(?i:of|by|are|is|include|including|from|with|drs?\.?))*[\s,:(]+)" + NM + r"(?:(?:\s*,\s*|\s+|\s*,?\s+(?:and|&)\s+)" + NM + r")*", lambda m: m.group(1) + m.group(2) + "[NAME]", v)
    v = re.sub(r"(\[NAME\])(?:(?:\s*,\s*|\s*,?\s+(?:and|&)\s+)(?:\[NAME\]|[A-Z][a-z]+[A-Za-z'\-]*))+", "[NAME]", v)
    return v[:n]
ttl = SMP.title.fillna("").str.replace(r"(?i)\b(supplement|fellowship|award|scholar)\s*[-:\u2013]\s*[A-Z][a-z]+(?:\s+[A-Z]\.?)?(?:\s+[A-Z][a-z'\-]+)+\s*$", lambda m: m.group(1) + " - [NAME]", regex=True)
SMP["title"] = ttl
aid = SMP.APPLICATION_ID.astype(float).astype("Int64").astype(str)
CC, CA = "CHD focus (Yes / Partly / No / Unsure)", "Age population (Pediatric / Adult / Both / Neither / Unclear)"
B = pd.DataFrame({"Review ID": SMP["Review ID"], "Project number": SMP.FULL_PROJECT_NUM, "Fiscal year": SMP.FY, "IC": SMP.IC, "Activity": SMP.ACT,
    "APPLICATION_ID": aid, "RePORTER": "https://reporter.nih.gov/project-details/" + aid, "Title": ttl.map(lambda x: clean(x, 500)),
    "Abstract / project summary": SMP.ABSTRACT_TEXT.map(lambda x: clean(x, 8000)),
    "Public health narrative": SMP.PHR.map(lambda x: clean(x, 4000) or "(no public health narrative in source record)"),
    CC: "", CA: "", "Reviewer code": "", "Review date (YYYY-MM-DD)": "", "Comments": ""})
readme = pd.read_excel("outputs/v2/chd_v2_review_BLIND.xlsx", sheet_name="READ ME FIRST")
hdr = readme.columns[0].replace("v2 fresh set", "V4 set"); lines = [l.replace("This file has 200", f"This file has {len(B)}") for l in readme.iloc[:, 0].fillna("").tolist()]
lines.insert(4, "5. Your review must be your own judgment; do not use AI tools or language models to label grants.")
blind = f"{OUT}/chd_v4_review_BLIND.xlsx"
with pd.ExcelWriter(blind) as xw:
    pd.DataFrame({hdr: lines}).to_excel(xw, sheet_name="READ ME FIRST", index=False); B.to_excel(xw, sheet_name="CHD_review", index=False)
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
           "tier", "t2_route", "t1_drop", "excl_v23", "kw", "rcdc", "age_v2", "previously_reviewed", "prior_IDs", "prior_reviews", "title"]]
W = SMP.groupby("stratum").agg(N_frame=("N_frame", "first"), n_sample=("n_sample", "first"), weight=("weight", "first"),
                               previously_reviewed=("previously_reviewed", lambda x: (x != "no").sum()), prior_with_label=("prior_reviews", lambda x: (x != "").sum()), pipeline_CHD=("tier", lambda x: (x != "Not CHD").sum()))
with pd.ExcelWriter(f"{OUT}/chd_v4_review_ANSWER_KEY.xlsx") as xw:
    pd.DataFrame({"ANSWER KEY — do not give to reviewers": [f"v2.3 rules. Seed {SEED}. Unit = NIH core project (FY2013-2026), one representative project-year (most recent FY with an abstract).",
        "Design: mostly CLEAR cases (A1 clear tier-1 CHD lesion grants; A2-A4 clear non-CHD) plus a small borderline share (B1-B3, 30 of 200). Strata partition all NIH core projects; weight = N_frame / n_sample, so weighted metrics refer to the whole portfolio.",
        "Because clear strata are oversampled, UNWEIGHTED metrics describe performance on clear cases and will be optimistic; use weighted metrics for portfolio inference.",
        "Previously reviewed grants allowed (owner-approved); prior IDs and labels (v2.3 reference, incl. overrides) in columns prior_IDs / prior_reviews. Order shuffled; V4 IDs do not encode prior IDs or strata.",
        "Score: CHD_KEY=outputs/v2.3/chd_v4_review_ANSWER_KEY.xlsx CHD_SCORE_OUT=outputs/v2.3/chd_v4_review_scoring.xlsx python3 R/15_v2_score_review.py <returned.xlsx>"]}).to_excel(xw, sheet_name="Notes", index=False)
    KEY.to_excel(xw, sheet_name="Key", index=False); W.to_excel(xw, sheet_name="Strata_weights")
assert not set(B.columns) & {"tier", "stratum", "weight", "previously_reviewed"}
pd.set_option("display.width", 250); print(W.to_string()); print(SMP.previously_reviewed.value_counts())
