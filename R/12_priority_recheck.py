# -*- coding: utf-8 -*-
"""Priority-only blind recheck for highest-impact disagreements (~100-150 rows)."""
import openpyxl
from openpyxl.styles import Font, Alignment, Protection
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation
from collections import Counter, defaultdict
from zipfile import ZipFile, ZIP_DEFLATED
import os, re, random, subprocess, tempfile

OUT = "outputs"
RET = f"{OUT}/reviewer_returned.xlsx"
KEY = f"{OUT}/chd_manual_check_ANSWER_KEY.xlsx"
SCORE = f"{OUT}/chd_review_scoring.xlsx"
SEED = 20261028
random.seed(SEED)

ARIAL = Font(name="Arial", size=11)
ARIAL_B = Font(name="Arial", size=11, bold=True)
WRAP = Alignment(wrap_text=True, vertical="top")
LOCK = Protection(locked=True)
UNLOCK = Protection(locked=False)

def load_sheet(path, sheet):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb[sheet]
    rows = ws.iter_rows(values_only=True)
    hdr = [str(h).strip() if h is not None else "" for h in next(rows)]
    data = [{hdr[i]: r[i] for i in range(len(hdr))} for r in rows]
    wb.close()
    return data

def col(d, *pats):
    for p in pats:
        for k in d:
            if re.search(p, k or "", re.I):
                return k
    raise KeyError(pats)

def s(v):
    return "" if v is None else str(v).strip()

def g(r, *pats, default=""):
    if not r: return default
    try: return s(r[col(r, *pats)])
    except Exception: return default

def truthy(v):
    if isinstance(v, bool): return v
    if isinstance(v, (int, float)): return v == 1
    return s(v).lower() in {"1", "true", "yes", "y"}

def repair_xlsx(path):
    tmp = path + ".repair.zip"
    with ZipFile(path, "r") as zin, ZipFile(tmp, "w", ZIP_DEFLATED) as zout:
        skip = {n for n in zin.namelist() if "/drawings/" in n or n.endswith(".vml")}
        for name in zin.namelist():
            if name in skip: continue
            data = zin.read(name)
            if name.endswith(".rels") or name == "[Content_Types].xml" or re.search(r"sheet\d+\.xml$", name):
                try: text = data.decode("utf-8")
                except Exception:
                    zout.writestr(name, data); continue
                text = re.sub(r"<Override[^>]*drawings/[^/]+\"[^/]*/>", "", text)
                text = re.sub(r"<Relationship[^>]*drawings/[^>]*/?>", "", text)
                text = re.sub(r"<Relationship[^>]*vmlDrawing[^>]*/?>", "", text)
                text = re.sub(r"<drawing[^/]*/>", "", text)
                text = re.sub(r"<drawing[^>]*>.*?</drawing>", "", text, flags=re.S)
                data = text.encode("utf-8")
            zout.writestr(name, data)
    os.replace(tmp, path)

# ---- USD lookup from R ----
rcode = r'''
source("R/00_setup.R")
u <- readRDS(wp("usd_rank.rds"))
# write CSV: FULL_PROJECT_NUM, CORE, FY-specific from C
C <- u$C
write.csv(C, "data/work/usd_by_proj_fy.csv", row.names=FALSE)
write.csv(u$core, "data/work/usd_by_core.csv", row.names=FALSE)
'''
subprocess.check_call(["Rscript", "-e", rcode], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

import csv
usd_fy = {}  # (FULL_PROJECT_NUM, FY) -> USD
usd_proj = defaultdict(float)  # FULL -> sum
usd_core = {}
with open("data/work/usd_by_proj_fy.csv") as f:
    for row in csv.DictReader(f):
        pn = row["FULL_PROJECT_NUM"]; fy = str(int(float(row["FY"]))) if row["FY"] else ""
        try: usd = float(row["USD"] or 0)
        except Exception: usd = 0.0
        usd_fy[(pn, fy)] = usd
        usd_proj[pn] += usd
with open("data/work/usd_by_core.csv") as f:
    for row in csv.DictReader(f):
        try: usd_core[row["CORE_PROJECT_NUM"]] = float(row["usd_sum"] or 0)
        except Exception: pass

def dollars(project, fy=None, core=None):
    if project and fy and (project, str(fy)) in usd_fy:
        return usd_fy[(project, str(fy))]
    if project and project in usd_proj:
        return usd_proj[project]
    if core and core in usd_core:
        return usd_core[core]
    return 0.0

# ---- Load joined rows (reuse scoring logic lightly) ----
Rchd = load_sheet(RET, "CHD_review")
Rage = load_sheet(RET, "Age_review")
Rcvd = load_sheet(RET, "CVD_review")
Kchd = load_sheet(KEY, "Key_CHD")
Kage = load_sheet(KEY, "Key_Age")
Kcvd = load_sheet(KEY, "Key_CVD")

def idx(rows):
    m = {}
    for r in rows:
        rid = g(r, r"^Review.?ID$")
        if rid: m[rid] = r
    return m
Kc, Ka, Kv = idx(Kchd), idx(Kage), idx(Kcvd)

def build_chd():
    out = []
    for r in Rchd:
        rid = g(r, r"^Review.?ID$"); k = Kc.get(rid, {})
        proj = g(k, r"Project.?number") or g(r, r"Project.?number")
        fy = g(r, r"Fiscal") or g(k, r"Fiscal")
        core = proj.split("-")[0] + "-" + proj.split("-")[1] if proj.count("-") >= 1 else proj
        # better: CORE is usually like R01HL123456
        core = re.sub(r"^[A-Z0-9]+", "", proj) if False else proj
        # use FULL project number for $; also try without suffix year
        usd = dollars(proj, fy)
        if usd == 0:
            # try stripping trailing year/activity variants
            base = re.sub(r"-\d{2}[A-Z]?$", "", proj) if proj else ""
            usd = dollars(proj) or dollars(base)
        row = dict(
            Review_ID=rid, Sheet="CHD_review",
            Title=g(r, r"^Title$") or g(k, r"^Title$"),
            Comments="",  # cleared for blind
            Rev_CHD=g(r, r"CHD.?focus"), Rev_AgePop=g(r, r"Age.?population"),
            Gold_CHD=g(k, r"Gold.?CHD"), Gold_age_pop=g(k, r"Gold.?age.?pop"),
            Stratum=g(k, r"^Stratum$"),
            Pipeline_kw=truthy(g(k, r"Pipeline.?keyword")),
            Project=proj, FY=fy, IC=g(r, r"^IC$"),
            Appl=g(r, r"APPLICATION"), Activity=g(r, r"^Activity$"),
            RePORTER=g(r, r"RePORTER") or (f"https://reporter.nih.gov/project-details/{g(r, r'APPLICATION')}" if g(r, r"APPLICATION") else ""),
            Abstract=g(r, r"Abstract"), PHR=g(r, r"Public.?health"),
            USD=usd,
        )
        out.append(row)
    return out

def build_age():
    out = []
    for r in Rage:
        rid = g(r, r"^Review.?ID$"); k = Ka.get(rid, {})
        proj = g(k, r"Project.?number") or g(r, r"Project.?number")
        fy = g(r, r"Fiscal") or g(k, r"Fiscal")
        usd = dollars(proj, fy) or dollars(proj)
        out.append(dict(
            Review_ID=rid, Sheet="Age_review",
            Title=g(r, r"^Title$") or g(k, r"^Title$"),
            Rev_Age=g(r, r"^Age.?focus$"), Gold_Age=g(k, r"Gold.?Age"),
            Stratum=g(k, r"^Stratum$"), Project=proj, FY=fy, IC=g(r, r"^IC$"),
            Appl=g(r, r"APPLICATION"),
            RePORTER=g(r, r"RePORTER") or (f"https://reporter.nih.gov/project-details/{g(r, r'APPLICATION')}" if g(r, r"APPLICATION") else ""),
            Abstract=g(r, r"Abstract"), PHR=g(r, r"Public.?health"),
            Pipeline_kw=truthy(g(k, r"Pipeline.?keyword")),
            USD=usd,
        ))
    return out

def build_cvd():
    out = []
    for r in Rcvd:
        rid = g(r, r"^Review.?ID$"); k = Kv.get(rid, {})
        proj = g(k, r"Project.?number") or g(r, r"Project.?number")
        fy = g(r, r"Fiscal") or g(k, r"Fiscal")
        usd = dollars(proj, fy) or dollars(proj)
        out.append(dict(
            Review_ID=rid, Sheet="CVD_review",
            Title=g(r, r"^Title$") or g(k, r"^Title$"),
            Rev_CVD=g(r, r"CVD.?substantial"), Rev_AgePop=g(r, r"Age.?population"),
            Gold_CVD=g(k, r"Gold.?CVD"), Gold_age_pop=g(k, r"Gold.?age.?pop"),
            Stratum=g(k, r"^Stratum$"), Project=proj, FY=fy, IC=g(r, r"^IC$"),
            Appl=g(r, r"APPLICATION"),
            RePORTER=g(r, r"RePORTER") or (f"https://reporter.nih.gov/project-details/{g(r, r'APPLICATION')}" if g(r, r"APPLICATION") else ""),
            Abstract=g(r, r"Abstract"), PHR=g(r, r"Public.?health"),
            Pipeline_kw=truthy(g(k, r"Pipeline.?keyword")),
            Pipeline_cvd=truthy(g(k, r"Pipeline.?CVD")),
            USD=usd,
        ))
    return out

Sc, Sa, Sv = build_chd(), build_age(), build_cvd()
print("USD coverage CHD nonzero:", sum(1 for x in Sc if x["USD"]>0), "/", len(Sc),
      "median", sorted(x["USD"] for x in Sc)[len(Sc)//2])

# ---- Selection rules ----
# Tier 1: keyword Yes → reviewer No (all)
T1 = [x for x in Sc if "Keyword" in x["Stratum"] and x["Gold_CHD"] == "Yes" and x["Rev_CHD"] == "No"]

# Tier 2: possible FNs — RCDC-only or near-miss rated Yes by reviewer (all)
T2 = [x for x in Sc if x["Rev_CHD"] == "Yes" and (
    "RCDC" in x["Stratum"] or "Near-miss" in x["Stratum"] or "near-miss" in x["Stratum"].lower())]

# Skip Partly-vs-Yes (low impact for headlines when Partly still counts as CHD)

AGE_FOCUS = {"Pediatric", "Adult", "Both"}
NEITHER = {"Neither / not age-specific", "Basic/non-age-specific"}

def age_moves_split_chd(x):
    """AgePop disagreement that moves pediatric/adult/both split."""
    g_, r_ = x["Gold_age_pop"], x["Rev_AgePop"]
    if not g_ or not r_ or g_ == r_: return False
    # Pediatric ↔ Neither
    if (g_ == "Pediatric" and r_ in NEITHER) or (r_ == "Pediatric" and g_ in NEITHER):
        return True
    # any Adult or Both involvement on either side (disagreement)
    if g_ in {"Adult", "Both"} or r_ in {"Adult", "Both"}:
        return True
    # Pediatric ↔ Adult / Both already covered; Pediatric ↔ Unclear less critical — skip Unclear-only
    if g_ == "Pediatric" and r_ in {"Adult", "Both"}: return True
    if r_ == "Pediatric" and g_ in {"Adult", "Both"}: return True
    return False

def age_moves_split_age(x):
    g_, r_ = x["Gold_Age"], x["Rev_Age"]
    if not g_ or not r_ or g_ == r_: return False
    # map Basic to Neither for split purposes
    g2 = "Neither / not age-specific" if g_ == "Basic/non-age-specific" else g_
    r2 = "Neither / not age-specific" if r_ == "Basic/non-age-specific" else r_
    if r_ == "Not CHD" or g_ == "Not CHD":
        return False  # CHD focus handled in T1/T2
    if (g2 == "Pediatric" and r2 in NEITHER) or (r2 == "Pediatric" and g2 in NEITHER):
        return True
    if g2 in {"Adult", "Both"} or r2 in {"Adult", "Both"}:
        return True
    return False

# Exclude projects already in T1/T2 from age tier to avoid duplicate effort on same grant for CHD sheet;
# Age_review can still include them (different question) but prefer unique projects.
t12_projects = {x["Project"] for x in T1 + T2}
t12_ids = {x["Review_ID"] for x in T1 + T2}

age_chd_cands = [x for x in Sc if age_moves_split_chd(x) and x["Review_ID"] not in t12_ids]
age_age_cands = [x for x in Sa if age_moves_split_age(x)]

# Prefer Age_review for age-focus adjudication when both exist for same project;
# take CHD AgePop only if project not already selected via Age_review.
age_chd_cands.sort(key=lambda x: -x["USD"])
age_age_cands.sort(key=lambda x: -x["USD"])

TARGET_LO, TARGET_HI = 100, 150
# Budget: T1+T2 fixed, then fill Tier3 age, then Tier4 CVD
n12 = len(T1) + len(T2)
# Aim total ~130: leave ~40 for age, ~30 for CVD (adjust)
AGE_BUDGET = 45
CVD_BUDGET = 40

T3 = []
seen_proj_age = set()
# First take Age_review by $
for x in age_age_cands:
    if len(T3) >= AGE_BUDGET: break
    if x["Project"] in seen_proj_age: continue
    T3.append(dict(x, tier=3, reason="Age_review split-moving, ranked by $"))
    seen_proj_age.add(x["Project"])
# Then CHD AgePop by $ for projects not yet covered
for x in age_chd_cands:
    if len([t for t in T3 if t["Sheet"] == "CHD_review"]) + len([t for t in T3 if t["Sheet"] == "Age_review"]) >= AGE_BUDGET:
        # allow a few more CHD AgePop if under budget of distinct age rows
        pass
    if len(T3) >= AGE_BUDGET: break
    if x["Project"] in seen_proj_age: continue
    T3.append(dict(x, tier=3, reason="CHD AgePop split-moving, ranked by $"))
    seen_proj_age.add(x["Project"])

# Tier 4: CVD gold Yes → Rev No, and Unsure; CHD-relevant (keyword CHD or in CHD keyword/RCDC/near-miss strata / Pipeline_kw)
# "CHD-relevant": Pipeline_kw OR Stratum mentions Keyword/RCDC/Near OR project appears in Sc keyword/RCDC/NM sets
chd_projects = {x["Project"] for x in Sc if x["Pipeline_kw"] or "Keyword" in x["Stratum"] or "RCDC" in x["Stratum"] or "Near-miss" in x["Stratum"]}
cvd_cands = []
for x in Sv:
    if x["Project"] not in chd_projects and not x["Pipeline_kw"]:
        # still include if stratum suggests CHD sample membership
        if "Keyword" not in x["Stratum"] and "RCDC" not in x["Stratum"] and "Near" not in x["Stratum"] and "CHD" not in x["Stratum"]:
            # CVD sheet strata may differ — check Pipeline_kw from key
            if not x["Pipeline_kw"]:
                continue
    if x["Gold_CVD"] == "Yes" and x["Rev_CVD"] == "No":
        cvd_cands.append(dict(x, reason="CVD gold Yes → Rev No"))
    elif x["Rev_CVD"] == "Unsure":
        cvd_cands.append(dict(x, reason="CVD Unsure"))
cvd_cands.sort(key=lambda x: -x["USD"])

T4 = []
for x in cvd_cands:
    if len(T4) >= CVD_BUDGET: break
    T4.append(dict(x, tier=4))

# Assemble with tiers for T1/T2
for x in T1:
    x["tier"] = 1; x["reason"] = "Keyword gold Yes → Rev No (FP affecting $)"
for x in T2:
    x["tier"] = 2; x["reason"] = "Possible FN: RCDC-only/near-miss Rev Yes"

# Cap total at 150
selected = T1 + T2 + T3 + T4
if len(selected) > TARGET_HI:
    # trim T3 then T4 from the bottom ($)
    overflow = len(selected) - TARGET_HI
    T3 = T3[:-overflow] if overflow < len(T3) else []
    if len(T1)+len(T2)+len(T3)+len(T4) > TARGET_HI:
        overflow = len(T1)+len(T2)+len(T3)+len(T4) - TARGET_HI
        T4 = T4[:-overflow] if overflow <= len(T4) else []
    selected = T1 + T2 + T3 + T4

# If under TARGET_LO, add more age then CVD
if len(selected) < TARGET_LO:
    need = TARGET_LO - len(selected)
    extra_age = [x for x in age_chd_cands + age_age_cands
                 if x["Review_ID"] not in {r["Review_ID"] for r in selected}
                 and x["Project"] not in seen_proj_age]
    extra_age.sort(key=lambda x: -x["USD"])
    for x in extra_age[:need]:
        T3.append(dict(x, tier=3, reason="Age split-moving fill to reach ~100"))
        seen_proj_age.add(x["Project"])
    selected = T1 + T2 + T3 + T4

print(f"Selected: T1={len(T1)} T2={len(T2)} T3={len(T3)} T4={len(T4)} total={len(selected)}")
print(f"$ T1={sum(x['USD'] for x in T1):,.0f} T2={sum(x['USD'] for x in T2):,.0f} T3={sum(x['USD'] for x in T3):,.0f} T4={sum(x['USD'] for x in T4):,.0f}")

# Split by sheet for blind workbook
by_sheet = defaultdict(list)
for x in selected:
    by_sheet[x["Sheet"]].append(x)

# ---- Build PRIORITY blind ----
def write_table(wb, name, rows, cols=None):
    ws = wb.create_sheet(name)
    if not rows:
        ws["A1"] = "(empty)"; return
    if cols is None: cols = list(rows[0].keys())
    for j, c in enumerate(cols, 1):
        cell = ws.cell(1, j, c); cell.font = ARIAL_B; cell.alignment = WRAP
    for i, row in enumerate(rows, 2):
        for j, c in enumerate(cols, 1):
            cell = ws.cell(i, j, row.get(c)); cell.font = ARIAL; cell.alignment = WRAP
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(cols))}{len(rows)+1}"
    for j, c in enumerate(cols, 1):
        ws.column_dimensions[get_column_letter(j)].width = min(42, max(12, len(str(c)) + 2))

def write_recheck_sheet(wb, sheet, rows, kind, map_out):
    ws = wb.create_sheet(sheet)
    if not rows:
        ws["A1"] = "No priority rows for this sheet."; return
    random.seed(SEED + {"CHD": 1, "AGE": 2, "CVD": 3}[kind])
    order = list(range(len(rows))); random.shuffle(order)
    rows = [rows[i] for i in order]

    if kind == "CHD":
        headers = ["Review ID", "Tier", "Project number", "Fiscal year", "IC", "Activity", "APPLICATION_ID",
                   "RePORTER", "Title", "Abstract / project summary", "Public health narrative",
                   "CHD focus (Yes / Partly / No / Unsure)",
                   "Age population (Pediatric / Adult / Both / Neither / Unclear)",
                   "Reviewer code", "Review date (YYYY-MM-DD)", "Comments"]
        unlock_from = 12
        dvs = [(12, '"Yes,Partly,No,Unsure"'),
               (13, '"Pediatric,Adult,Both,Neither / not age-specific,Unclear"')]
        tier_col = 2
    elif kind == "AGE":
        headers = ["Review ID", "Tier", "Project number", "Fiscal year", "IC", "APPLICATION_ID",
                   "RePORTER", "Title", "Abstract / project summary", "Public health narrative",
                   "Age focus", "Reviewer code", "Review date (YYYY-MM-DD)", "Comments"]
        unlock_from = 11
        dvs = [(11, '"Pediatric,Adult,Both,Basic/non-age-specific,Unclear,Not CHD"')]
        tier_col = 2
    else:
        headers = ["Review ID", "Tier", "Project number", "Fiscal year", "IC", "APPLICATION_ID",
                   "RePORTER", "Title", "Abstract / project summary", "Public health narrative",
                   "CVD substantial focus (Yes / No / Unsure)",
                   "Age population (Pediatric / Adult / Both / Neither / Unclear)",
                   "Reviewer code", "Review date (YYYY-MM-DD)", "Comments"]
        unlock_from = 11
        dvs = [(11, '"Yes,No,Unsure"'),
               (12, '"Pediatric,Adult,Both,Neither / not age-specific,Unclear"')]
        tier_col = 2

    for j, h in enumerate(headers, 1):
        cell = ws.cell(1, j, h); cell.font = ARIAL_B; cell.alignment = WRAP; cell.protection = LOCK

    for i, x in enumerate(rows, 1):
        rid2 = f"P-{kind}-{i:03d}"
        map_out.append(dict(Priority_ID=rid2, Round1_Review_ID=x["Review_ID"], kind=kind,
                            Tier=x["tier"], reason=x.get("reason", ""), row=x))
        tier_label = f"Tier {x['tier']}"
        if kind == "CHD":
            vals = [rid2, tier_label, x["Project"], x["FY"], x["IC"], x.get("Activity", ""), x["Appl"],
                    x["RePORTER"], x["Title"], x["Abstract"], x["PHR"], "", "", "", "", ""]
        elif kind == "AGE":
            vals = [rid2, tier_label, x["Project"], x["FY"], x["IC"], x["Appl"],
                    x["RePORTER"], x["Title"], x["Abstract"], x["PHR"], "", "", "", ""]
        else:
            vals = [rid2, tier_label, x["Project"], x["FY"], x["IC"], x["Appl"],
                    x["RePORTER"], x["Title"], x["Abstract"], x["PHR"], "", "", "", "", ""]
        for j, v in enumerate(vals, 1):
            cell = ws.cell(i + 1, j, v)
            cell.font = ARIAL; cell.alignment = WRAP
            cell.protection = UNLOCK if j >= unlock_from else LOCK
        url = x["RePORTER"]
        if url:
            cell = ws.cell(i + 1, headers.index("RePORTER") + 1)
            cell.hyperlink = url; cell.value = url
            cell.font = Font(name="Arial", size=11, color="0563C1", underline="single")
            cell.protection = LOCK
        # Tier column locked (visible but not editable reason)
        ws.cell(i + 1, tier_col).protection = LOCK

    n = len(rows); nc = len(headers)
    ws.freeze_panes = "C2"
    ws.auto_filter.ref = f"A1:{get_column_letter(nc)}{n+1}"
    widths = {"Review ID": 12, "Tier": 8, "Project number": 16, "Fiscal year": 10, "IC": 8,
              "Activity": 10, "APPLICATION_ID": 14, "RePORTER": 36, "Title": 40,
              "Abstract / project summary": 50, "Public health narrative": 36}
    for j, h in enumerate(headers, 1):
        ws.column_dimensions[get_column_letter(j)].width = widths.get(h, 18)
    for col_idx, formula in dvs:
        dv = DataValidation(type="list", formula1=formula, allow_blank=True)
        ws.add_data_validation(dv)
        dv.add(f"{get_column_letter(col_idx)}2:{get_column_letter(col_idx)}{n+1}")
    ws.protection.sheet = True
    ws.protection.enable()
    ws.protection.autoFilter = False
    ws.protection.selectUnlockedCells = False

bw = openpyxl.Workbook(); bw.remove(bw.active)
ws = bw.create_sheet("READ ME FIRST", 0)
readme = [
    "PRIORITY BLIND RECHECK — highest-impact disagreements only",
    "",
    "PURPOSE",
    "1. Pipeline definitions remain the primary analysis. This short list asks a second reviewer to",
    "   re-judge only the disagreements most likely to change headline CHD dollars or the",
    "   pediatric / adult / both split. Rows are labeled Tier 1 / 2 / 3 (higher tier = higher priority).",
    "   The tier number does NOT reveal why the row was selected.",
    "",
    "RULES",
    "2. Work alone. Do not look at round-1 answers, the answer key, or the scoring file.",
    "3. Judge only from Title, Abstract, Public health narrative, and the RePORTER link.",
    "4. Ignore residual person names / [NAME] placeholders.",
    "5. Use the dropdowns. Add initials and date on every row you complete.",
    "6. Save and return this file. Brief Comments are optional.",
    "",
    "DEFINITIONS (same as round 1; pipeline definitions stay primary)",
    "7. CHD focus:",
    "   - Yes = primary/substantial congenital heart disease or named structural lesion / Fontan / HLHS / ToF / TGA / etc.",
    "   - Partly = CHD is one aim or clear motivation only (or mixed congenital + acquired).",
    "   - No = not CHD (coronary-only CAD, channelopathy/arrhythmia without congenital lesion, acquired valve disease, etc.).",
    "   - Unsure = cannot decide from the available text.",
    "8. Age population (CHD_review and CVD_review):",
    "   - Pediatric = fetal / neonatal / infant / child / adolescent (under 18).",
    "   - Adult = adult or ACHD (18+).",
    "   - Both = lifespan, transition, or explicit pediatric+adult cohorts.",
    "   - Neither / not age-specific = basic science, animal, iPSC, methods without a human age target.",
    "   - Unclear = cannot tell.",
    "9. Age_review Age focus: Pediatric / Adult / Both / Basic/non-age-specific / Unclear / Not CHD.",
    "10. CVD substantial focus: Yes / No / Unsure. Heart, vessels, hypertension, stroke, cardiomyopathy,",
    "    arrhythmia, CV surgery/devices, or CHD count as Yes.",
    "",
    "TIME",
    f"11. This file has about {len(selected)} rows. Typical pace ~1–2 minutes each → roughly {len(selected)*1.5/60:.0f}–{len(selected)*2/60:.0f} hours.",
    "    Complete Tier 1 first, then Tier 2, then Tier 3 (filter on the Tier column if helpful).",
]
for i, line in enumerate(readme, 1):
    cell = ws.cell(i, 1, line); cell.font = ARIAL; cell.alignment = WRAP
ws.column_dimensions["A"].width = 120
ws.protection.sheet = True; ws.protection.enable()

map_all = []
write_recheck_sheet(bw, "CHD_review", by_sheet["CHD_review"], "CHD", map_all)
write_recheck_sheet(bw, "Age_review", by_sheet["Age_review"], "AGE", map_all)
write_recheck_sheet(bw, "CVD_review", by_sheet["CVD_review"], "CVD", map_all)

blind_path = f"{OUT}/chd_manual_recheck_PRIORITY_BLIND.xlsx"
bw.properties.creator = ""; bw.properties.lastModifiedBy = ""
bw.properties.title = "CHD priority blind recheck"
bw.save(blind_path)
repair_xlsx(blind_path)
print("wrote", blind_path)

# ---- Answer key ----
rk = openpyxl.Workbook(); rk.remove(rk.active)
ws = rk.create_sheet("Selection_rule")
rules = [
    ["PRIORITY RECHECK — SELECTION RULE (do not give to reviewers)"],
    [""],
    ["Pipeline definitions remain primary. This pack resolves only highest-impact disagreements."],
    ["Target size: roughly 100–150 rows total."],
    [""],
    ["Tier 1 — all keyword gold Yes → reviewer No (false positives affecting CHD $)."],
    ["Tier 2 — all possible false negatives: RCDC-only or near-miss strata rated Yes by reviewer."],
    ["Skipped — Partly vs Yes disagreements (low impact when Partly still counts as CHD in primary def)."],
    ["Tier 3 — age-focus disagreements that move the pediatric/adult/both split"],
    ["  (gold Pediatric ↔ reviewer Neither/Basic; any Adult or Both disagreement),"],
    ["  ranked by project-year award $, preferring Age_review then CHD AgePop; unique projects; budget ~45."],
    ["Tier 4 — CVD gold Yes → reviewer No, and CVD Unsure, among CHD-relevant projects,"],
    ["  ranked by project-year award $; budget ~40."],
    [""],
    ["Tier labels shown to reviewers are only 'Tier 1/2/3' (Tier 4 shown as Tier 3 in the blind file"],
    ["  if needed for simplicity — ACTUALLY we show Tier 1/2/3 matching internal tiers 1/2/3; Tier 4 shown as Tier 3)."],
]
# User asked: Tier 1/2/3 visible without revealing reason. We have 4 internal tiers.
# Map display: Tier 1, Tier 2, Tier 3 for age+CVD combined? Or show Tier 1/2/3 where CVD is Tier 3?
# User said: "Include a priority tier column visible to the reviewer only as 'Tier 1/2/3'"
# So only 3 visible tiers. Map: T1→1, T2→2, T3+T4→3 (or T1, T2, T3 for age and use Tier 3 for CVD too).
# Better: display Tier 1, 2, 3 where internal T4 also displays as Tier 3 (both are "lower priority than FP/FN").
# I already wrote Tier {x['tier']} with tier 4 — need to remap display to max 3.

# Fix: remap display tiers in blind file - actually already saved. Re-open and fix Tier 4 → Tier 3 display,
# OR regenerate. Let me remap: display_tier = min(tier, 3)

for i, row in enumerate(rules, 1):
    ws.cell(i, 1, row[0]).font = ARIAL
ws.column_dimensions["A"].width = 110

# Recount $ by tier
def usd_sum(rows): return sum(x["USD"] for x in rows)

stake = [
    dict(Tier="Tier 1 (display Tier 1)", Internal="keyword Yes→No FP", N=len(T1),
         USD_at_stake=usd_sum(T1), Rule="All included"),
    dict(Tier="Tier 2 (display Tier 2)", Internal="RCDC/near-miss Rev Yes FN", N=len(T2),
         USD_at_stake=usd_sum(T2), Rule="All included"),
    dict(Tier="Tier 3 (display Tier 3)", Internal="Age split-moving by $", N=len(T3),
         USD_at_stake=usd_sum(T3), Rule=f"Top {len(T3)} by $; Pediatric↔Neither or Adult/Both"),
    dict(Tier="Tier 4 (display Tier 3)", Internal="CVD Yes→No + Unsure CHD-relevant by $", N=len(T4),
         USD_at_stake=usd_sum(T4), Rule=f"Top {len(T4)} by $ among CHD-relevant"),
    dict(Tier="TOTAL", Internal="", N=len(selected), USD_at_stake=usd_sum(selected), Rule=f"Target {TARGET_LO}–{TARGET_HI}"),
]
write_table(rk, "Dollars_at_stake", stake)

# Reminder note about display mapping
ws.cell(len(rules) + 2, 1, "DISPLAY MAPPING: Internal Tier 4 is shown to reviewers as 'Tier 3' (only Tier 1/2/3 labels are used).").font = ARIAL
ws.cell(len(rules) + 3, 1, f"Counts: T1={len(T1)} T2={len(T2)} T3_age={len(T3)} T4_cvd={len(T4)} TOTAL={len(selected)}").font = ARIAL

def write_map(name, kind, rows_src):
    rows = [m for m in map_all if m["kind"] == kind]
    # rebuild map_all after display fix — for now write from selected directly
    out = []
    sheet_rows = [x for x in selected if x["Sheet"] == {"CHD": "CHD_review", "AGE": "Age_review", "CVD": "CVD_review"}[kind]]
    # Use map_all which has Priority_ID after shuffle
    for m in rows:
        x = m["row"]
        disp = min(x["tier"], 3)
        if kind == "CHD":
            out.append(dict(Priority_ID=m["Priority_ID"], Round1_Review_ID=m["Round1_Review_ID"],
                            Display_Tier=f"Tier {disp}", Internal_Tier=x["tier"], Reason=m["reason"],
                            Stratum=x["Stratum"], Gold_CHD=x.get("Gold_CHD"), Rev_CHD=x.get("Rev_CHD"),
                            Gold_age_pop=x.get("Gold_age_pop"), Rev_AgePop=x.get("Rev_AgePop"),
                            USD=x["USD"], Project=x["Project"], FY=x["FY"], Title=x["Title"]))
        elif kind == "AGE":
            out.append(dict(Priority_ID=m["Priority_ID"], Round1_Review_ID=m["Round1_Review_ID"],
                            Display_Tier=f"Tier {disp}", Internal_Tier=x["tier"], Reason=m["reason"],
                            Stratum=x["Stratum"], Gold_Age=x.get("Gold_Age"), Rev_Age=x.get("Rev_Age"),
                            USD=x["USD"], Project=x["Project"], FY=x["FY"], Title=x["Title"]))
        else:
            out.append(dict(Priority_ID=m["Priority_ID"], Round1_Review_ID=m["Round1_Review_ID"],
                            Display_Tier=f"Tier {disp}", Internal_Tier=x["tier"], Reason=m["reason"],
                            Stratum=x["Stratum"], Gold_CVD=x.get("Gold_CVD"), Rev_CVD=x.get("Rev_CVD"),
                            Gold_age_pop=x.get("Gold_age_pop"), Rev_AgePop=x.get("Rev_AgePop"),
                            USD=x["USD"], Project=x["Project"], FY=x["FY"], Title=x["Title"]))
    write_table(rk, name, out)

# Fix blind file: remap Tier 4 → Tier 3 for display
wb_fix = openpyxl.load_workbook(blind_path)
for sn in ["CHD_review", "Age_review", "CVD_review"]:
    if sn not in wb_fix.sheetnames: continue
    ws = wb_fix[sn]
    hdr = [c.value for c in next(ws.iter_rows(min_row=1, max_row=1))]
    if "Tier" not in hdr: continue
    ti = hdr.index("Tier") + 1
    for row in ws.iter_rows(min_row=2, max_row=ws.max_row):
        v = row[ti - 1].value
        if v == "Tier 4":
            row[ti - 1].value = "Tier 3"
wb_fix.properties.creator = ""; wb_fix.properties.lastModifiedBy = ""
wb_fix.save(blind_path)
repair_xlsx(blind_path)

# Rebuild map_all display is fine; write maps
# Need map_all from the write — already populated. Fix tier 4 in map reasons.
write_map("Map_CHD", "CHD", T1 + T2 + [x for x in T3 if x["Sheet"] == "CHD_review"])
write_map("Map_Age", "AGE", [x for x in T3 if x["Sheet"] == "Age_review"])
write_map("Map_CVD", "CVD", T4)

key_path = f"{OUT}/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx"
rk.properties.creator = ""; rk.properties.lastModifiedBy = ""
rk.properties.title = "CHD priority recheck ANSWER KEY"
rk.save(key_path)
repair_xlsx(key_path)
print("wrote", key_path)

# ---- Leak scan ----
FORBIDDEN_HDR = re.compile(r"(?i)^(gold[_\s]|pipeline[_\s]|stratum$|discordance|rule that fired|matched terms|prior_|reason$)")
TOKEN = re.compile(
    r"(?i)\b(Gold_CHD|Gold_Age|Gold_CVD|Gold_age_pop|Pipeline_keyword|Pipeline_RCDC|Pipeline_CVD|"
    r"Discordance|Matched terms|Rule that fired|Prior_CHD|answer key|false positive|false negative)\b")
wb2 = openpyxl.load_workbook(blind_path, data_only=True)
hits = []
for sn in wb2.sheetnames:
    if sn == "READ ME FIRST": continue
    ws = wb2[sn]
    hdr = [c.value for c in next(ws.iter_rows(min_row=1, max_row=1))]
    for h in hdr:
        if h and FORBIDDEN_HDR.search(str(h)): hits.append((sn, "hdr", h))
    # Tier values should only be Tier 1/2/3
    if "Tier" in hdr:
        ti = hdr.index("Tier")
        for row in ws.iter_rows(min_row=2, values_only=True):
            if row[ti] not in ("Tier 1", "Tier 2", "Tier 3", None):
                hits.append((sn, "tier", row[ti]))
    for row in ws.iter_rows(min_row=2, values_only=True):
        for j, v in enumerate(row):
            if v is None: continue
            t = str(v)
            if len(t) > 120:
                if TOKEN.search(t) and "discordance" not in t.lower():  # allow CHB discordance
                    # still allow natural 'discordance'
                    m = TOKEN.search(t)
                    if m and m.group(0).lower() != "discordance":
                        hits.append((sn, "long", m.group(0))); 
                continue
            m = TOKEN.search(t)
            if m and m.group(0).lower() != "discordance":
                hits.append((sn, hdr[j] if j < len(hdr) else j, t[:80]))
# Answer cols empty?
for sn in ["CHD_review", "Age_review", "CVD_review"]:
    if sn not in wb2.sheetnames: continue
    ws = wb2[sn]
    rows = list(ws.iter_rows(values_only=True))
    hdr = rows[0]
    ans = [i for i, h in enumerate(hdr) if h and any(k in str(h).lower() for k in
           ["focus", "age population", "age focus", "initial", "comment", "date"])]
    for i in ans:
        filled = sum(1 for r in rows[1:] if r[i] not in (None, ""))
        if filled and "initial" not in str(hdr[i]).lower() and "date" not in str(hdr[i]).lower() and "comment" not in str(hdr[i]).lower():
            hits.append((sn, "answers_filled", hdr[i], filled))
        elif "focus" in str(hdr[i]).lower() or "population" in str(hdr[i]).lower():
            if filled:
                hits.append((sn, "answers_filled", hdr[i], filled))
wb2.close()
print("leak hits:", len(hits))
for h in hits[:15]:
    print(" ", h)

# Sheet counts
print("\n=== PRIORITY PACK ===")
print(f"T1 FP: n={len(T1)} USD={usd_sum(T1):,.0f}")
print(f"T2 FN: n={len(T2)} USD={usd_sum(T2):,.0f}")
print(f"T3 Age: n={len(T3)} USD={usd_sum(T3):,.0f} (CHD AgePop={sum(1 for x in T3 if x['Sheet']=='CHD_review')}, Age_review={sum(1 for x in T3 if x['Sheet']=='Age_review')})")
print(f"T4 CVD: n={len(T4)} USD={usd_sum(T4):,.0f}")
print(f"TOTAL n={len(selected)} USD={usd_sum(selected):,.0f}")
print("By sheet:", {k: len(v) for k, v in by_sheet.items()})
print("Display tiers: Tier1=T1, Tier2=T2, Tier3=T3+T4")
