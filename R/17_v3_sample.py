"""17_v3_sample.py -- draw the v3 200-grant blinded review set covering ALL v2.1 tiers, with portfolio weights.
Frame = all NIH core projects FY2013-2026 (one representative project-year per core: most recent FY with an abstract).
Previously reviewed grants may be included (user-approved); order is shuffled and IDs (V3-###) do not encode prior IDs.
Outputs: outputs/v2.1/chd_v3_review_BLIND.xlsx, outputs/v2.1/chd_v3_review_ANSWER_KEY.xlsx
Then run R/14b_v2_scrub_names.py with CHD_BLIND=outputs/v2.1/chd_v3_review_BLIND.xlsx."""
import os, re, numpy as np, pandas as pd, pyreadr, importlib.util
from openpyxl import load_workbook
from openpyxl.styles import Font, Alignment
from openpyxl.worksheet.datavalidation import DataValidation
spec = importlib.util.spec_from_file_location("rules", "R/13_v2_rules.py"); R = importlib.util.module_from_spec(spec); spec.loader.exec_module(R)
WHR = os.environ.get("CHD_WHR_WORK", "data/raw/whr_work"); OUT = "outputs/v2.1"; SEED = 20261104
D = pd.read_pickle("data/work/v2.1_classified.pkl")
pool_txt = pd.read_pickle("data/work/v2_pool.pkl")[["FY", "FULL_PROJECT_NUM", "title"]]
D["dev_title"] = R.cnt(D.title.fillna("").str.lower(), R.DEV) > 0
D["stratum"] = np.select([D.tier1, D.tier2 & (D.t2_route == "developmental science"), D.tier2, ~D.chd_v2 & D.rcdc,
                          ~D.chd_v2 & (D.s_str.between(1, 2) | D.dev_title)],
    ["V1 Tier 1 CHD-focused", "V2 Tier 2 developmental science", "V3 Tier 2 pediatric device / trainee",
     "V4 RCDC CHD only (not v2.1)", "V5 Near-boundary negative (1-2 strong terms or developmental title)"], "V6 Other CHD-signal negative")
D["in_pool"] = True
# no-signal portfolio stratum: every other NIH project-year (from C.rds)
C = pyreadr.read_r("data/work/C.rds")[None][["FY", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "IC", "ACT", "USD", "title"]]
C = C[~C.FULL_PROJECT_NUM.isin(D.FULL_PROJECT_NUM) | ~C.set_index(["FY", "FULL_PROJECT_NUM"]).index.isin(D.set_index(["FY", "FULL_PROJECT_NUM"]).index)]
C = C[~C.CORE_PROJECT_NUM.isin(D.CORE_PROJECT_NUM)].assign(stratum="V7 No CHD signal (rest of NIH portfolio)", tier="Not CHD", t2_route="", t1_drop="", age_v2="Not age-specific", rcdc=False, kw=False)
ALL = pd.concat([D, C], ignore_index=True)
# core-level unit: most recent project-year; stratum of that project-year
ALL = ALL.sort_values("FY", ascending=False).drop_duplicates("CORE_PROJECT_NUM")
ALLOC = {"V1 Tier 1 CHD-focused": 60, "V2 Tier 2 developmental science": 35, "V3 Tier 2 pediatric device / trainee": 25,
         "V4 RCDC CHD only (not v2.1)": 30, "V5 Near-boundary negative (1-2 strong terms or developmental title)": 30,
         "V6 Other CHD-signal negative": 12, "V7 No CHD signal (rest of NIH portfolio)": 8}
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
SMP["previously_reviewed"] = np.select([SMP.CORE_PROJECT_NUM.isin(prior_cores), SMP.CORE_PROJECT_NUM.isin(v2_cores)], ["v1 review", "v2 fresh set"], "no")
SMP = SMP.sample(frac=1, random_state=SEED + 7).reset_index(drop=True); SMP["Review ID"] = [f"V3-{i+1:03d}" for i in range(len(SMP))]
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
hdr = readme.columns[0].replace("v2 fresh set", "v3 set"); lines = [l.replace("This file has 200", f"This file has {len(B)}") for l in readme.iloc[:, 0].fillna("").tolist()]
lines.insert(4, "5. Your review must be your own judgment; do not use AI tools or language models to label grants.")
blind = f"{OUT}/chd_v3_review_BLIND.xlsx"
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
           "tier", "t2_route", "t1_drop", "kw", "rcdc", "age_v2", "previously_reviewed", "title"]]
W = SMP.groupby("stratum").agg(N_frame=("N_frame", "first"), n_sample=("n_sample", "first"), weight=("weight", "first"),
                               previously_reviewed=("previously_reviewed", lambda x: (x != "no").sum()))
with pd.ExcelWriter(f"{OUT}/chd_v3_review_ANSWER_KEY.xlsx") as xw:
    pd.DataFrame({"ANSWER KEY — do not give to reviewers": [f"v2.1 rules. Seed {SEED}. Unit = NIH core project (FY2013-2026), one representative project-year (most recent FY with an abstract).",
        "Strata cover every v2.1 tier plus RCDC-only, near-boundary, other CHD-signal negatives and the rest of the NIH portfolio; weight = N_frame / n_sample, so weighted metrics refer to all NIH core projects.",
        "Previously reviewed grants are allowed (user-approved); see column previously_reviewed. Order shuffled; V3 IDs do not encode prior IDs.",
        "Score: CHD_KEY=outputs/v2.1/chd_v3_review_ANSWER_KEY.xlsx CHD_SCORE_OUT=outputs/v2.1/chd_v3_review_scoring.xlsx python3 R/15_v2_score_review.py <returned.xlsx>"]}).to_excel(xw, sheet_name="Notes", index=False)
    KEY.to_excel(xw, sheet_name="Key", index=False); W.to_excel(xw, sheet_name="Strata_weights")
assert not set(B.columns) & {"tier", "stratum", "weight", "previously_reviewed"}
pd.set_option("display.width", 250); print(W.to_string()); print(SMP.previously_reviewed.value_counts())
