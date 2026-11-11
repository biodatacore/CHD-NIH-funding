# -*- coding: utf-8 -*-
"""Score reviewer_returned.xlsx vs answer key; flag disagreements; build round-2 blind recheck."""
import openpyxl
from openpyxl.styles import Font, Alignment, Protection, Border, Side, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation
from collections import Counter, defaultdict
from zipfile import ZipFile, ZIP_DEFLATED
import io, os, re, random, math, shutil, tempfile

OUT = "outputs"
RET = f"{OUT}/reviewer_returned.xlsx"
KEY = f"{OUT}/chd_manual_check_ANSWER_KEY.xlsx"
SEED = 20261027
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
    data = []
    for r in rows:
        data.append({hdr[i]: r[i] for i in range(len(hdr))})
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

def cohen_kappa(xs, ys, levels=None):
    pairs = [(s(x), s(y)) for x, y in zip(xs, ys) if s(x) and s(y)]
    if not pairs: return dict(kappa=None, n=0, po=None, pe=None, table={})
    if levels is None:
        levels = sorted({a for a, _ in pairs} | {b for _, b in pairs})
    tab = {(a, b): 0 for a in levels for b in levels}
    for a, b in pairs:
        if a not in levels or b not in levels: continue
        tab[(a, b)] += 1
    n = sum(tab.values())
    if n == 0: return dict(kappa=None, n=0, po=None, pe=None, table=tab)
    po = sum(tab[(l, l)] for l in levels) / n
    row = {l: sum(tab[(l, b)] for b in levels) for l in levels}
    colc = {l: sum(tab[(a, l)] for a in levels) for l in levels}
    pe = sum(row[l] * colc[l] for l in levels) / (n * n)
    kappa = None if pe >= 1 else (po - pe) / (1 - pe)
    return dict(kappa=kappa, n=n, po=po, pe=pe, table=tab, levels=levels)

def conf_rows(tab, levels, name_a="Reviewer", name_b="Gold"):
    out = []
    for a in levels:
        for b in levels:
            out.append({name_a: a, name_b: b, "N": tab.get((a, b), 0)})
    return out

def pr_stats(pred, truth):
    pairs = [(bool(p), bool(t)) for p, t in zip(pred, truth)]
    tp = sum(p and t for p, t in pairs)
    fp = sum(p and not t for p, t in pairs)
    fn = sum((not p) and t for p, t in pairs)
    tn = sum((not p) and not t for p, t in pairs)
    return dict(tp=tp, fp=fp, fn=fn, tn=tn,
                precision=(tp / (tp + fp)) if (tp + fp) else None,
                recall=(tp / (tp + fn)) if (tp + fn) else None,
                agreement=((tp + tn) / len(pairs)) if pairs else None)

# ---- Load ----
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

Sc, Sa, Sv = [], [], []
for r in Rchd:
    rid = g(r, r"^Review.?ID$"); k = Kc.get(rid, {})
    Sc.append(dict(
        Review_ID=rid, Title=g(r, r"^Title$"), Comments=g(r, r"^Comments$"),
        Rev_CHD=g(r, r"CHD.?focus"), Rev_AgePop=g(r, r"Age.?population"),
        Gold_CHD=g(k, r"Gold.?CHD"), Gold_age_pop=g(k, r"Gold.?age.?pop"),
        Stratum=g(k, r"^Stratum$"), Pipeline_kw=truthy(g(k, r"Pipeline.?keyword")),
        Pipeline_rcdc=truthy(g(k, r"Pipeline.?RCDC")),
        Project=g(k, r"Project.?number") or g(r, r"Project.?number"),
        FY=g(r, r"Fiscal"), IC=g(r, r"^IC$"), Appl=g(r, r"APPLICATION"),
        RePORTER=g(r, r"RePORTER") or (f"https://reporter.nih.gov/project-details/{g(r, r'APPLICATION')}" if g(r, r"APPLICATION") else ""),
        Abstract=g(r, r"Abstract"), PHR=g(r, r"Public.?health"),
        Activity=g(r, r"^Activity$"), KeyTitle=g(k, r"^Title$"),
        Prior=g(k, r"Prior.?CHD"),
    ))
for r in Rage:
    rid = g(r, r"^Review.?ID$"); k = Ka.get(rid, {})
    Sa.append(dict(
        Review_ID=rid, Title=g(r, r"^Title$"), Comments=g(r, r"^Comments$"),
        Rev_Age=g(r, r"^Age.?focus$"), Gold_Age=g(k, r"Gold.?Age"),
        Stratum=g(k, r"^Stratum$"), Pipeline_kw=truthy(g(k, r"Pipeline.?keyword")),
        Project=g(k, r"Project.?number") or g(r, r"Project.?number"),
        FY=g(r, r"Fiscal"), IC=g(r, r"^IC$"), Appl=g(r, r"APPLICATION"),
        RePORTER=g(r, r"RePORTER") or (f"https://reporter.nih.gov/project-details/{g(r, r'APPLICATION')}" if g(r, r"APPLICATION") else ""),
        Abstract=g(r, r"Abstract"), PHR=g(r, r"Public.?health"), KeyTitle=g(k, r"^Title$"),
        Prior_age=g(k, r"Prior.?age"),
    ))
for r in Rcvd:
    rid = g(r, r"^Review.?ID$"); k = Kv.get(rid, {})
    Sv.append(dict(
        Review_ID=rid, Title=g(r, r"^Title$"), Comments=g(r, r"^Comments$"),
        Rev_CVD=g(r, r"CVD.?substantial"), Rev_AgePop=g(r, r"Age.?population"),
        Gold_CVD=g(k, r"Gold.?CVD"), Gold_age_pop=g(k, r"Gold.?age.?pop"),
        Stratum=g(k, r"^Stratum$"), Pipeline_cvd=truthy(g(k, r"Pipeline.?CVD")),
        Project=g(k, r"Project.?number") or g(r, r"Project.?number"),
        FY=g(r, r"Fiscal"), IC=g(r, r"^IC$"), Appl=g(r, r"APPLICATION"),
        RePORTER=g(r, r"RePORTER") or (f"https://reporter.nih.gov/project-details/{g(r, r'APPLICATION')}" if g(r, r"APPLICATION") else ""),
        Abstract=g(r, r"Abstract"), PHR=g(r, r"Public.?health"), KeyTitle=g(k, r"^Title$"),
    ))

# ---- Flags ----
for x in Sc:
    x["answered"] = bool(x["Rev_CHD"])
    x["match_exact"] = x["answered"] and x["Rev_CHD"] == x["Gold_CHD"]
    x["match_lenient"] = x["answered"] and (
        (x["Rev_CHD"] in ("Yes", "Partly") and x["Gold_CHD"] in ("Yes", "Partly")) or
        (x["Rev_CHD"] == "No" and x["Gold_CHD"] == "No"))
    x["disagree_CHD"] = x["answered"] and (x["Rev_CHD"] != x["Gold_CHD"])  # includes Unsure, Partly≠Yes
    x["disagree_AgePop"] = bool(x["Rev_AgePop"]) and x["Rev_AgePop"] != x["Gold_age_pop"]
    x["flag_round2"] = x["disagree_CHD"] or x["disagree_AgePop"] or x["Rev_CHD"] == "Unsure"

for x in Sa:
    x["answered"] = bool(x["Rev_Age"])
    x["match_exact"] = x["answered"] and x["Rev_Age"] == x["Gold_Age"]
    x["disagree_Age"] = x["answered"] and x["Rev_Age"] != x["Gold_Age"]
    x["flag_round2"] = x["disagree_Age"]

for x in Sv:
    x["answered_any"] = bool(x["Rev_CVD"])
    x["answered"] = x["answered_any"] and x["Rev_CVD"] != "Unsure"
    x["match_exact"] = x["answered"] and x["Rev_CVD"] == x["Gold_CVD"]
    x["disagree_CVD"] = x["answered_any"] and (x["Rev_CVD"] == "Unsure" or x["Rev_CVD"] != x["Gold_CVD"])
    x["disagree_AgePop"] = bool(x["Rev_AgePop"]) and x["Rev_AgePop"] != x["Gold_age_pop"]
    x["flag_round2"] = x["disagree_CVD"] or x["disagree_AgePop"]

id_chd = [x["Review_ID"] for x in Sc if x["flag_round2"]]
id_age = [x["Review_ID"] for x in Sa if x["flag_round2"]]
id_cvd = [x["Review_ID"] for x in Sv if x["flag_round2"]]
print(f"Round-2 counts: CHD={len(id_chd)} Age={len(id_age)} CVD={len(id_cvd)}")

# ---- Metrics ----
k_chd = cohen_kappa([x["Rev_CHD"] for x in Sc], [x["Gold_CHD"] for x in Sc])
k_chd_bin = cohen_kappa(
    ["Pos" if x["Rev_CHD"] in ("Yes", "Partly") else ("Neg" if x["Rev_CHD"] == "No" else "") for x in Sc],
    ["Pos" if x["Gold_CHD"] in ("Yes", "Partly") else "Neg" for x in Sc],
    ["Pos", "Neg"])
k_age = cohen_kappa([x["Rev_Age"] for x in Sa], [x["Gold_Age"] for x in Sa])
k_agepop_c = cohen_kappa([x["Rev_AgePop"] for x in Sc], [x["Gold_age_pop"] for x in Sc])
k_cvd = cohen_kappa(
    [x["Rev_CVD"] for x in Sv if x["Rev_CVD"] != "Unsure"],
    [x["Gold_CVD"] for x in Sv if x["Rev_CVD"] != "Unsure"],
    ["Yes", "No"])
k_agepop_v = cohen_kappa([x["Rev_AgePop"] for x in Sv], [x["Gold_age_pop"] for x in Sv])

kw = [x for x in Sc if "Keyword" in x["Stratum"]]
rc = [x for x in Sc if "RCDC" in x["Stratum"]]
nm = [x for x in Sc if "Near-miss" in x["Stratum"] or "near-miss" in x["Stratum"].lower()]

st_s = pr_stats([x["Pipeline_kw"] for x in Sc], [x["Rev_CHD"] == "Yes" for x in Sc])
st_l = pr_stats([x["Pipeline_kw"] for x in Sc], [x["Rev_CHD"] in ("Yes", "Partly") for x in Sc])

# Weighted recall: use universe core sizes from C.rds via a quick R call or estimate from strata
# Keyword stratum = all unique cores (689). RCDC-only sample 95 of ~? Near-miss 49 of ~?
# Try reading a saved sample object or config note; fall back to sample sizes as unweighted + note.
try:
    import subprocess, textwrap
    rcode = textwrap.dedent(r'''
    source("R/00_setup.R"); C <- readRDS(wp("C.rds"))
    cat(uniqueN(C[kw==TRUE, CORE_PROJECT_NUM]), "\n")
    cat(uniqueN(C[rcdc & !kw, CORE_PROJECT_NUM]), "\n")
    cat(uniqueN(C[!kw & !rcdc & s_str %in% 1:2 & !is.na(ABSTRACT_TEXT) & nchar(ABSTRACT_TEXT)>=40, CORE_PROJECT_NUM]), "\n")
    ''')
    out = subprocess.check_output(["Rscript", "-e", rcode], text=True, stderr=subprocess.DEVNULL).strip().splitlines()
    n_kw_core, n_rc_core, n_nm_core = map(int, out[:3])
except Exception as e:
    print("core counts fallback:", e)
    n_kw_core, n_rc_core, n_nm_core = len(kw), max(len(rc), 1) * 5, max(len(nm), 1) * 20

w_rc = n_rc_core / max(len(rc), 1)
w_nm = n_nm_core / max(len(nm), 1)
tp_s = sum(1 for x in kw if x["Pipeline_kw"] and x["Rev_CHD"] == "Yes")
tp_l = sum(1 for x in kw if x["Pipeline_kw"] and x["Rev_CHD"] in ("Yes", "Partly"))
fn_rc_s = sum(1 for x in rc if x["Rev_CHD"] == "Yes")
fn_rc_l = sum(1 for x in rc if x["Rev_CHD"] in ("Yes", "Partly"))
fn_nm_s = sum(1 for x in nm if x["Rev_CHD"] == "Yes")
fn_nm_l = sum(1 for x in nm if x["Rev_CHD"] in ("Yes", "Partly"))
recall_w_s = tp_s / (tp_s + fn_rc_s * w_rc + fn_nm_s * w_nm) if (tp_s + fn_rc_s * w_rc + fn_nm_s * w_nm) else None
recall_w_l = tp_l / (tp_l + fn_rc_l * w_rc + fn_nm_l * w_nm) if (tp_l + fn_rc_l * w_rc + fn_nm_l * w_nm) else None

cvd_ok = [x for x in Sv if x["Rev_CVD"] != "Unsure"]
cvd_st = pr_stats([x["Pipeline_cvd"] for x in cvd_ok], [x["Rev_CVD"] == "Yes" for x in cvd_ok])

fp_rate = sum(1 for x in kw if x["Rev_CHD"] == "No") / max(len(kw), 1)
partly_rate = sum(1 for x in kw if x["Rev_CHD"] == "Partly") / max(len(kw), 1)

age_levels = ["Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear", "Not CHD"]
age_pr = []
for lev in age_levels:
    p = [x["Rev_Age"] == lev for x in Sa]
    t = [x["Gold_Age"] == lev for x in Sa]
    np_, nt = sum(p), sum(t)
    tp = sum(a and b for a, b in zip(p, t))
    age_pr.append(dict(category=lev, precision=(tp / np_) if np_ else None,
                       recall=(tp / nt) if nt else None, n_rev=np_, n_gold=nt))

# Prior comparison
prior_agree = prior_n = 0
for x in Sc:
    if x["Prior"] in ("Yes", "Partly", "No", "yes", "partial", "no"):
        prior_n += 1
        # map prior labels
        pr = x["Prior"].lower()
        pr_m = "Yes" if pr == "yes" else ("Partly" if pr.startswith("part") else "No")
        if pr_m == x["Rev_CHD"] or (pr_m in ("Yes", "Partly") and x["Rev_CHD"] in ("Yes", "Partly")):
            prior_agree += 1

# ---- Disagreement tables ----
def title_of(x):
    return x["Title"] or x["KeyTitle"]

Disc_CHD = []
for x in Sc:
    if not x["flag_round2"]: continue
    flag = "CHD+AgePop" if x["disagree_CHD"] and x["disagree_AgePop"] else (
        "CHD" if x["disagree_CHD"] or x["Rev_CHD"] == "Unsure" else "AgePop")
    Disc_CHD.append(dict(
        Review_ID=x["Review_ID"], Sheet="CHD_review", Stratum=x["Stratum"], Title=title_of(x),
        Rev_CHD=x["Rev_CHD"], Gold_CHD=x["Gold_CHD"], Rev_AgePop=x["Rev_AgePop"],
        Gold_age_pop=x["Gold_age_pop"], Flag=flag, Comments=x["Comments"], Project=x["Project"]))

Disc_Age = []
for x in Sa:
    if not x["flag_round2"]: continue
    Disc_Age.append(dict(
        Review_ID=x["Review_ID"], Sheet="Age_review", Stratum=x["Stratum"], Title=title_of(x),
        Rev_Age=x["Rev_Age"], Gold_Age=x["Gold_Age"], Flag="Age", Comments=x["Comments"], Project=x["Project"]))

Disc_CVD = []
for x in Sv:
    if not x["flag_round2"]: continue
    flag = "CVD+AgePop" if x["disagree_CVD"] and x["disagree_AgePop"] else (
        "CVD" if x["disagree_CVD"] else "AgePop")
    Disc_CVD.append(dict(
        Review_ID=x["Review_ID"], Sheet="CVD_review", Stratum=x["Stratum"], Title=title_of(x),
        Rev_CVD=x["Rev_CVD"], Gold_CVD=x["Gold_CVD"], Rev_AgePop=x["Rev_AgePop"],
        Gold_age_pop=x["Gold_age_pop"], Flag=flag, Comments=x["Comments"], Project=x["Project"]))

# Patterns with examples
def ex(ids, n=5):
    return "; ".join(ids[:n])

patterns = [
    dict(Pattern="Keyword CHD gold Yes, reviewer No",
         N=sum(1 for x in kw if x["Rev_CHD"] == "No"),
         Example_Review_IDs=ex([x["Review_ID"] for x in kw if x["Rev_CHD"] == "No"]),
         Example_titles=ex([title_of(x)[:80] for x in kw if x["Rev_CHD"] == "No"])),
    dict(Pattern="RCDC-only gold Partly, reviewer Yes (possible keyword FN)",
         N=sum(1 for x in rc if x["Rev_CHD"] == "Yes"),
         Example_Review_IDs=ex([x["Review_ID"] for x in rc if x["Rev_CHD"] == "Yes"]),
         Example_titles=ex([title_of(x)[:80] for x in rc if x["Rev_CHD"] == "Yes"])),
    dict(Pattern="Near-miss gold No, reviewer Yes (possible keyword FN)",
         N=sum(1 for x in nm if x["Rev_CHD"] == "Yes"),
         Example_Review_IDs=ex([x["Review_ID"] for x in nm if x["Rev_CHD"] == "Yes"]),
         Example_titles=ex([title_of(x)[:80] for x in nm if x["Rev_CHD"] == "Yes"])),
    dict(Pattern="Keyword gold Yes, reviewer Partly",
         N=sum(1 for x in kw if x["Rev_CHD"] == "Partly"),
         Example_Review_IDs=ex([x["Review_ID"] for x in kw if x["Rev_CHD"] == "Partly"]),
         Example_titles=ex([title_of(x)[:80] for x in kw if x["Rev_CHD"] == "Partly"])),
    dict(Pattern="AgePop: gold Pediatric vs rev Neither",
         N=sum(1 for x in Sc if x["Gold_age_pop"] == "Pediatric" and x["Rev_AgePop"] == "Neither / not age-specific"),
         Example_Review_IDs=ex([x["Review_ID"] for x in Sc if x["Gold_age_pop"] == "Pediatric" and x["Rev_AgePop"] == "Neither / not age-specific"]),
         Example_titles=ex([title_of(x)[:80] for x in Sc if x["Gold_age_pop"] == "Pediatric" and x["Rev_AgePop"] == "Neither / not age-specific"])),
    dict(Pattern="AgePop: gold Neither vs rev Pediatric",
         N=sum(1 for x in Sc if x["Gold_age_pop"] == "Neither / not age-specific" and x["Rev_AgePop"] == "Pediatric"),
         Example_Review_IDs=ex([x["Review_ID"] for x in Sc if x["Gold_age_pop"] == "Neither / not age-specific" and x["Rev_AgePop"] == "Pediatric"]),
         Example_titles=ex([title_of(x)[:80] for x in Sc if x["Gold_age_pop"] == "Neither / not age-specific" and x["Rev_AgePop"] == "Pediatric"])),
    dict(Pattern="Age_review: rev Not CHD vs gold age category",
         N=sum(1 for x in Sa if x["Rev_Age"] == "Not CHD" and x["Gold_Age"] != "Not CHD"),
         Example_Review_IDs=ex([x["Review_ID"] for x in Sa if x["Rev_Age"] == "Not CHD" and x["Gold_Age"] != "Not CHD"]),
         Example_titles=ex([title_of(x)[:80] for x in Sa if x["Rev_Age"] == "Not CHD" and x["Gold_Age"] != "Not CHD"])),
    dict(Pattern="CVD Unsure",
         N=sum(1 for x in Sv if x["Rev_CVD"] == "Unsure"),
         Example_Review_IDs=ex([x["Review_ID"] for x in Sv if x["Rev_CVD"] == "Unsure"]),
         Example_titles=ex([title_of(x)[:80] for x in Sv if x["Rev_CVD"] == "Unsure"])),
    dict(Pattern="CVD gold Yes, reviewer No",
         N=sum(1 for x in Sv if x["Gold_CVD"] == "Yes" and x["Rev_CVD"] == "No"),
         Example_Review_IDs=ex([x["Review_ID"] for x in Sv if x["Gold_CVD"] == "Yes" and x["Rev_CVD"] == "No"]),
         Example_titles=ex([title_of(x)[:80] for x in Sv if x["Gold_CVD"] == "Yes" and x["Rev_CVD"] == "No"])),
]

# Age share among keyword positives
kw_pos = [x for x in kw if x["Rev_CHD"] in ("Yes", "Partly")]
age_share_rev = Counter(x["Rev_AgePop"] for x in kw_pos)
age_share_gold = Counter(x["Gold_age_pop"] for x in kw)

# Headline impact note
# If we treat reviewer No as FP for keyword CHD dollars, scale by (1-fp_rate).
# Age split: use reviewer AgePop among Yes/Partly.

Summary = [
    dict(Section="Completion", Metric="CHD rows answered", Value=sum(x["answered"] for x in Sc), Note=f"of {len(Sc)}"),
    dict(Section="Completion", Metric="CHD Unsure", Value=sum(x["Rev_CHD"] == "Unsure" for x in Sc), Note=""),
    dict(Section="Completion", Metric="Age rows answered", Value=sum(x["answered"] for x in Sa), Note=f"of {len(Sa)}"),
    dict(Section="Completion", Metric="CVD rows answered (any)", Value=sum(x["answered_any"] for x in Sv), Note=f"of {len(Sv)}"),
    dict(Section="Completion", Metric="CVD Unsure", Value=sum(x["Rev_CVD"] == "Unsure" for x in Sv), Note=""),
    dict(Section="CHD agreement", Metric="Exact agreement", Value=round(sum(x["match_exact"] for x in Sc)/len(Sc), 4), Note=""),
    dict(Section="CHD agreement", Metric="Lenient agreement (Yes/Partly grouped)", Value=round(sum(x["match_lenient"] for x in Sc)/len(Sc), 4), Note=""),
    dict(Section="CHD agreement", Metric="Cohen kappa (4-way)", Value=None if k_chd["kappa"] is None else round(k_chd["kappa"], 4), Note=f"n={k_chd['n']}"),
    dict(Section="CHD agreement", Metric="Cohen kappa (Pos=Yes/Partly vs No)", Value=None if k_chd_bin["kappa"] is None else round(k_chd_bin["kappa"], 4), Note=""),
    dict(Section="Keyword classifier vs reviewer", Metric="Precision (truth Rev Yes)", Value=None if st_s["precision"] is None else round(st_s["precision"], 4), Note=f"TP={st_s['tp']} FP={st_s['fp']}"),
    dict(Section="Keyword classifier vs reviewer", Metric="Precision (truth Rev Yes|Partly)", Value=None if st_l["precision"] is None else round(st_l["precision"], 4), Note=f"TP={st_l['tp']} FP={st_l['fp']}"),
    dict(Section="Keyword classifier vs reviewer", Metric="Recall unweighted (Yes)", Value=None if st_s["recall"] is None else round(st_s["recall"], 4), Note="among reviewed rows only"),
    dict(Section="Keyword classifier vs reviewer", Metric="Recall sample-weighted (Yes)", Value=None if recall_w_s is None else round(recall_w_s, 4),
         Note=f"FN from RCDC-only x{w_rc:.2f} + near-miss x{w_nm:.2f}; cores kw={n_kw_core} rc={n_rc_core} nm={n_nm_core}"),
    dict(Section="Keyword classifier vs reviewer", Metric="Recall sample-weighted (Yes|Partly)", Value=None if recall_w_l is None else round(recall_w_l, 4), Note=""),
    dict(Section="CHD by stratum", Metric="Keyword cores: Rev Yes/Partly/No", Value="",
         Note=f"Yes={sum(x['Rev_CHD']=='Yes' for x in kw)} Partly={sum(x['Rev_CHD']=='Partly' for x in kw)} No={sum(x['Rev_CHD']=='No' for x in kw)}"),
    dict(Section="CHD by stratum", Metric="RCDC-only: Rev Yes/Partly/No", Value="",
         Note=f"Yes={sum(x['Rev_CHD']=='Yes' for x in rc)} Partly={sum(x['Rev_CHD']=='Partly' for x in rc)} No={sum(x['Rev_CHD']=='No' for x in rc)}"),
    dict(Section="CHD by stratum", Metric="Near-miss: Rev Yes/Partly/No", Value="",
         Note=f"Yes={sum(x['Rev_CHD']=='Yes' for x in nm)} Partly={sum(x['Rev_CHD']=='Partly' for x in nm)} No={sum(x['Rev_CHD']=='No' for x in nm)}"),
    dict(Section="Age_review", Metric="Exact agreement", Value=round(sum(x["match_exact"] for x in Sa)/len(Sa), 4), Note=""),
    dict(Section="Age_review", Metric="Cohen kappa", Value=None if k_age["kappa"] is None else round(k_age["kappa"], 4), Note=f"n={k_age['n']}"),
    dict(Section="Age population (CHD sheet)", Metric="Agreement", Value=round(sum(x["Rev_AgePop"]==x["Gold_age_pop"] for x in Sc)/len(Sc), 4), Note=""),
    dict(Section="Age population (CHD sheet)", Metric="Cohen kappa", Value=None if k_agepop_c["kappa"] is None else round(k_agepop_c["kappa"], 4), Note=""),
    dict(Section="CVD", Metric="Agreement (excl Unsure)", Value=round(sum(x["match_exact"] for x in cvd_ok)/max(len(cvd_ok),1), 4), Note=""),
    dict(Section="CVD", Metric="Cohen kappa Yes/No", Value=None if k_cvd["kappa"] is None else round(k_cvd["kappa"], 4), Note=""),
    dict(Section="CVD", Metric="Precision (pipeline vs Rev Yes)", Value=None if cvd_st["precision"] is None else round(cvd_st["precision"], 4), Note=""),
    dict(Section="CVD", Metric="Recall (pipeline vs Rev Yes)", Value=None if cvd_st["recall"] is None else round(cvd_st["recall"], 4), Note=""),
    dict(Section="Age population (CVD sheet)", Metric="Agreement", Value=round(sum(x["Rev_AgePop"]==x["Gold_age_pop"] for x in Sv)/len(Sv), 4), Note=""),
    dict(Section="Age population (CVD sheet)", Metric="Cohen kappa", Value=None if k_agepop_v["kappa"] is None else round(k_agepop_v["kappa"], 4), Note=""),
    dict(Section="Prior judgments", Metric="Rows with prior CHD judgment", Value=prior_n, Note="from answer key Prior_CHD_judgment"),
    dict(Section="Prior judgments", Metric="Lenient agree prior vs this reviewer", Value=round(prior_agree/prior_n, 4) if prior_n else None, Note=""),
    dict(Section="Round-2 recheck", Metric="CHD_review rows to recheck", Value=len(id_chd), Note="any CHD or AgePop disagreement / Unsure"),
    dict(Section="Round-2 recheck", Metric="Age_review rows to recheck", Value=len(id_age), Note=""),
    dict(Section="Round-2 recheck", Metric="CVD_review rows to recheck", Value=len(id_cvd), Note=""),
    dict(Section="Headline impact", Metric="Keyword-stratum FP rate (Rev=No)", Value=round(fp_rate, 4),
         Note="If applied to keyword CHD $, scale by (1-FP); Partly still counted as CHD in primary def"),
    dict(Section="Headline impact", Metric="Keyword-stratum Partly rate", Value=round(partly_rate, 4), Note=""),
    dict(Section="Headline impact", Metric="Reviewer-corrected CHD $ scale (excl No)", Value=round(1 - fp_rate, 4),
         Note="Approximate; dollars not reweighted by project size here"),
]

# ---- Write scoring workbook ----
def write_table(wb, name, rows, cols=None):
    ws = wb.create_sheet(name)
    if not rows:
        ws["A1"] = "(empty)"; return
    if cols is None: cols = list(rows[0].keys())
    for j, c in enumerate(cols, 1):
        cell = ws.cell(1, j, c); cell.font = ARIAL_B; cell.alignment = WRAP
    for i, row in enumerate(rows, 2):
        for j, c in enumerate(cols, 1):
            cell = ws.cell(i, j, row.get(c))
            cell.font = ARIAL; cell.alignment = WRAP
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(cols))}{len(rows)+1}"
    for j, c in enumerate(cols, 1):
        ws.column_dimensions[get_column_letter(j)].width = min(40, max(12, len(c) + 2))

wb = openpyxl.Workbook(); wb.remove(wb.active)
write_table(wb, "Summary", Summary)
write_table(wb, "Confusion_CHD", conf_rows(k_chd["table"], k_chd["levels"]))
# by stratum
conf_s = []
for st in sorted({x["Stratum"] for x in Sc}):
    sub = [x for x in Sc if x["Stratum"] == st]
    levels = sorted({x["Rev_CHD"] for x in sub} | {x["Gold_CHD"] for x in sub})
    for a in levels:
        for b in levels:
            n = sum(1 for x in sub if x["Rev_CHD"] == a and x["Gold_CHD"] == b)
            if n: conf_s.append(dict(Stratum=st, Reviewer=a, Gold=b, N=n))
write_table(wb, "Confusion_CHD_by_stratum", conf_s)
write_table(wb, "Confusion_Age", conf_rows(k_age["table"], k_age["levels"]))
write_table(wb, "Confusion_AgePop_CHD", conf_rows(k_agepop_c["table"], k_agepop_c["levels"]))
write_table(wb, "Confusion_CVD", conf_rows(k_cvd["table"], k_cvd["levels"]))
write_table(wb, "Confusion_AgePop_CVD", conf_rows(k_agepop_v["table"], k_agepop_v["levels"]))
write_table(wb, "Age_category_PR", age_pr)
write_table(wb, "Disagreements_CHD", Disc_CHD)
write_table(wb, "Disagreements_Age", Disc_Age)
write_table(wb, "Disagreements_CVD", Disc_CVD)
write_table(wb, "Disagreement_patterns", patterns)
write_table(wb, "Age_share_keyword_rev",
            [dict(Age=a, N=n, pct=round(100*n/max(len(kw_pos),1), 2)) for a, n in age_share_rev.most_common()])
write_table(wb, "Age_share_keyword_gold",
            [dict(Age=a, N=n, pct=round(100*n/max(len(kw),1), 2)) for a, n in age_share_gold.most_common()])
# Full flagged row dump with Disagree=TRUE
write_table(wb, "CHD_all_flagged", [
    dict(Review_ID=x["Review_ID"], Stratum=x["Stratum"], Rev_CHD=x["Rev_CHD"], Gold_CHD=x["Gold_CHD"],
         Rev_AgePop=x["Rev_AgePop"], Gold_age_pop=x["Gold_age_pop"],
         disagree_CHD=x["disagree_CHD"], disagree_AgePop=x["disagree_AgePop"],
         Title=title_of(x), Comments=x["Comments"]) for x in Sc if x["flag_round2"]])
write_table(wb, "Age_all_flagged", [
    dict(Review_ID=x["Review_ID"], Stratum=x["Stratum"], Rev_Age=x["Rev_Age"], Gold_Age=x["Gold_Age"],
         Title=title_of(x), Comments=x["Comments"]) for x in Sa if x["flag_round2"]])
write_table(wb, "CVD_all_flagged", [
    dict(Review_ID=x["Review_ID"], Stratum=x["Stratum"], Rev_CVD=x["Rev_CVD"], Gold_CVD=x["Gold_CVD"],
         Rev_AgePop=x["Rev_AgePop"], Gold_age_pop=x["Gold_age_pop"],
         disagree_CVD=x["disagree_CVD"], disagree_AgePop=x["disagree_AgePop"],
         Title=title_of(x), Comments=x["Comments"]) for x in Sv if x["flag_round2"]])

score_path = f"{OUT}/chd_review_scoring.xlsx"
wb.properties.creator = ""; wb.properties.lastModifiedBy = ""; wb.properties.title = "CHD review scoring"
wb.save(score_path)
print("wrote", score_path)

# ---- Round-2 blind ----
def repair_xlsx(path):
    """Strip drawing/vml refs that break openpyxl round-trips after some writers."""
    tmp = path + ".repair.zip"
    with ZipFile(path, "r") as zin, ZipFile(tmp, "w", ZIP_DEFLATED) as zout:
        skip = set()
        for name in zin.namelist():
            if "/drawings/" in name or name.endswith(".vml"):
                skip.add(name)
        for name in zin.namelist():
            if name in skip: continue
            data = zin.read(name)
            if name.endswith(".rels") or name == "[Content_Types].xml" or re.search(r"sheet\d+\.xml$", name):
                try:
                    text = data.decode("utf-8")
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

def style_header(ws, ncols):
    for j in range(1, ncols + 1):
        c = ws.cell(1, j); c.font = ARIAL_B; c.alignment = WRAP; c.protection = LOCK

def write_recheck_sheet(wb, sheet, rows, kind, map_out):
    ws = wb.create_sheet(sheet)
    if not rows:
        ws["A1"] = "No disagreements for this sheet."; return
    random.seed(SEED + hash(kind) % 10000)
    order = list(range(len(rows))); random.shuffle(order)
    rows = [rows[i] for i in order]
    if kind == "CHD":
        headers = ["Review ID", "Project number", "Fiscal year", "IC", "Activity", "APPLICATION_ID",
                   "RePORTER", "Title", "Abstract / project summary", "Public health narrative",
                   "CHD focus (Yes / Partly / No / Unsure)",
                   "Age population (Pediatric / Adult / Both / Neither / Unclear)",
                   "Reviewer code", "Review date (YYYY-MM-DD)", "Comments"]
        unlock_from = 11
        dvs = [
            (11, '"Yes,Partly,No,Unsure"'),
            (12, '"Pediatric,Adult,Both,Neither / not age-specific,Unclear"'),
        ]
    elif kind == "AGE":
        headers = ["Review ID", "Project number", "Fiscal year", "IC", "APPLICATION_ID",
                   "RePORTER", "Title", "Abstract / project summary", "Public health narrative",
                   "Age focus", "Reviewer code", "Review date (YYYY-MM-DD)", "Comments"]
        unlock_from = 10
        dvs = [(10, '"Pediatric,Adult,Both,Basic/non-age-specific,Unclear,Not CHD"')]
    else:
        headers = ["Review ID", "Project number", "Fiscal year", "IC", "APPLICATION_ID",
                   "RePORTER", "Title", "Abstract / project summary", "Public health narrative",
                   "CVD substantial focus (Yes / No / Unsure)",
                   "Age population (Pediatric / Adult / Both / Neither / Unclear)",
                   "Reviewer code", "Review date (YYYY-MM-DD)", "Comments"]
        unlock_from = 10
        dvs = [
            (10, '"Yes,No,Unsure"'),
            (11, '"Pediatric,Adult,Both,Neither / not age-specific,Unclear"'),
        ]

    for j, h in enumerate(headers, 1):
        cell = ws.cell(1, j, h); cell.font = ARIAL_B; cell.alignment = WRAP; cell.protection = LOCK

    for i, x in enumerate(rows, 1):
        rid2 = f"R2-{kind}-{i:03d}"
        map_out.append(dict(Round2_ID=rid2, Round1_Review_ID=x["Review_ID"], kind=kind, row=x))
        if kind == "CHD":
            vals = [rid2, x["Project"], x["FY"], x["IC"], x.get("Activity", ""), x["Appl"],
                    x["RePORTER"], title_of(x), x["Abstract"], x["PHR"], "", "", "", "", ""]
        elif kind == "AGE":
            vals = [rid2, x["Project"], x["FY"], x["IC"], x["Appl"],
                    x["RePORTER"], title_of(x), x["Abstract"], x["PHR"], "", "", "", ""]
        else:
            vals = [rid2, x["Project"], x["FY"], x["IC"], x["Appl"],
                    x["RePORTER"], title_of(x), x["Abstract"], x["PHR"], "", "", "", "", ""]
        for j, v in enumerate(vals, 1):
            cell = ws.cell(i + 1, j, v)
            cell.font = ARIAL; cell.alignment = WRAP
            cell.protection = UNLOCK if j >= unlock_from else LOCK
        # hyperlink
        url = x["RePORTER"]
        if url:
            cell = ws.cell(i + 1, headers.index("RePORTER") + 1)
            cell.hyperlink = url; cell.value = url
            cell.font = Font(name="Arial", size=11, color="0563C1", underline="single")
            cell.protection = LOCK

    n = len(rows); nc = len(headers)
    ws.freeze_panes = "B2"
    ws.auto_filter.ref = f"A1:{get_column_letter(nc)}{n+1}"
    widths = {"Review ID": 14, "Project number": 16, "Fiscal year": 10, "IC": 8, "Activity": 10,
              "APPLICATION_ID": 14, "RePORTER": 36, "Title": 40,
              "Abstract / project summary": 50, "Public health narrative": 36}
    for j, h in enumerate(headers, 1):
        ws.column_dimensions[get_column_letter(j)].width = widths.get(h, 18)
    for col_idx, formula in dvs:
        dv = DataValidation(type="list", formula1=formula, allow_blank=True)
        dv.error = "Pick from the list"; dv.errorTitle = "Invalid"
        ws.add_data_validation(dv)
        dv.add(f"{get_column_letter(col_idx)}2:{get_column_letter(col_idx)}{n+1}")
    ws.protection.sheet = True
    ws.protection.enable()
    ws.protection.autoFilter = False
    ws.protection.selectUnlockedCells = False

bw = openpyxl.Workbook(); bw.remove(bw.active)
ws = bw.create_sheet("READ ME FIRST", 0)
readme = [
    "ROUND-2 BLIND RECHECK — disagreement rows only",
    "",
    "PURPOSE",
    "1. These grants had a difference between the first reviewer’s answers and the automated gold labels",
    "   (including Partly ≠ Yes, Unsure, or age-population mismatches). Re-judge them independently.",
    "",
    "RULES",
    "2. Work alone. Do not look at round-1 answers, the answer key, or anyone else’s judgments.",
    "3. Judge only from Title, Abstract, Public health narrative, and the RePORTER link for the same application.",
    "4. Ignore residual person names / [NAME] placeholders if any remain.",
    "5. Use the dropdowns. Add initials and date on every row you complete.",
    "6. Save and return this file when done. Leave Comments blank unless a brief note helps adjudication.",
    "",
    "DEFINITIONS (same as round 1)",
    "7. CHD focus:",
    "   - Yes = primary/substantial congenital heart disease or named structural lesion / Fontan / HLHS / ToF / TGA / etc.",
    "   - Partly = CHD is one aim or clear motivation only (or mixed congenital + acquired).",
    "   - No = not CHD (coronary-only CAD, channelopathy/arrhythmia without congenital lesion, acquired valve disease, etc.).",
    "   - Unsure = cannot decide from the available text.",
    "8. Age population (CHD_review and CVD_review):",
    "   - Pediatric = fetal / neonatal / infant / child / adolescent focus (under 18).",
    "   - Adult = adult or ACHD focus (18+).",
    "   - Both = lifespan, transition, or explicit pediatric+adult cohorts.",
    "   - Neither / not age-specific = basic science, animal, iPSC, methods without a human age target.",
    "   - Unclear = cannot tell.",
    "9. Age_review Age focus: Pediatric / Adult / Both / Basic/non-age-specific / Unclear / Not CHD.",
    "   Use Not CHD if the grant is not about congenital heart disease at all.",
    "10. CVD substantial focus: Yes / No / Unsure. Heart, vessels, hypertension, stroke, cardiomyopathy,",
    "    arrhythmia, CV surgery/devices, or CHD count as Yes.",
    "",
    "TIME",
    "11. Typical pace ~1–2 minutes per row. Prioritize completing every dropdown over long comments.",
]
for i, line in enumerate(readme, 1):
    cell = ws.cell(i, 1, line); cell.font = ARIAL; cell.alignment = WRAP
ws.column_dimensions["A"].width = 120
ws.protection.sheet = True; ws.protection.enable()

map_all = []
write_recheck_sheet(bw, "CHD_review", [x for x in Sc if x["flag_round2"]], "CHD", map_all)
write_recheck_sheet(bw, "Age_review", [x for x in Sa if x["flag_round2"]], "AGE", map_all)
write_recheck_sheet(bw, "CVD_review", [x for x in Sv if x["flag_round2"]], "CVD", map_all)

blind2 = f"{OUT}/chd_manual_recheck_round2_BLIND.xlsx"
bw.properties.creator = ""; bw.properties.lastModifiedBy = ""
bw.properties.title = "CHD round-2 blind recheck"
bw.save(blind2)
repair_xlsx(blind2)
print("wrote", blind2)

# Leak scan
LEAK = re.compile(
    r"(?i)(gold_|pipeline_|stratum|discord|rule that fired|matched terms|prior_|answer.?key|"
    r"keyword.?CHD|rcdc.?only|near-miss|agree/disagree|"
    r"\bYes\b.*\bPartly\b.*pipeline|Gold_CHD|Gold_Age|Gold_CVD)")
# tighter forbidden headers/content
FORBIDDEN_HDR = re.compile(
    r"(?i)^(gold_|pipeline_|stratum|discordance|rule that fired|matched terms|prior_)")
FORBIDDEN_BODY = re.compile(
    r"(?i)(Gold_CHD|Gold_Age|Gold_CVD|Gold_age_pop|Pipeline_keyword|Pipeline_RCDC|Pipeline_CVD|"
    r"Rule that fired|Matched terms|Discordance|Prior_CHD|Prior_age|answer key)")

wb2 = openpyxl.load_workbook(blind2, data_only=True)
leak_hits = []
for sn in wb2.sheetnames:
    if sn == "READ ME FIRST":
        continue  # instructions intentionally mention gold/labels conceptually
    ws = wb2[sn]
    hdr = [c.value for c in next(ws.iter_rows(min_row=1, max_row=1))]
    for h in hdr:
        if h and FORBIDDEN_HDR.search(str(h)):
            leak_hits.append((sn, "header", h))
    for row in ws.iter_rows(min_row=2, values_only=True):
        for v in row:
            if v is None: continue
            if FORBIDDEN_BODY.search(str(v)):
                leak_hits.append((sn, "body", str(v)[:80])); break
wb2.close()
print("leak hits:", len(leak_hits))
for h in leak_hits[:10]:
    print(" ", h)

# Round-2 answer key
rk = openpyxl.Workbook(); rk.remove(rk.active)
ws = rk.create_sheet("Notes")
notes = [
    "ROUND-2 ANSWER KEY — do not give to reviewers.",
    "Maps Round2_ID -> Round1_Review_ID -> gold labels and round-1 reviewer answers.",
    "Disagreement definition: any non-exact match on the sheet's primary label(s), including Unsure and Partly≠Yes, and age-population mismatches on CHD/CVD sheets.",
    f"Counts: CHD={len(id_chd)} Age={len(id_age)} CVD={len(id_cvd)}",
]
for i, n in enumerate(notes, 1):
    ws.cell(i, 1, n).font = ARIAL
ws.column_dimensions["A"].width = 120

def write_map(name, kind):
    rows = [m for m in map_all if m["kind"] == kind]
    out = []
    for m in rows:
        x = m["row"]
        if kind == "CHD":
            out.append(dict(Round2_ID=m["Round2_ID"], Round1_Review_ID=m["Round1_Review_ID"],
                            Stratum=x["Stratum"], Gold_CHD=x["Gold_CHD"], Gold_age_pop=x["Gold_age_pop"],
                            Round1_Rev_CHD=x["Rev_CHD"], Round1_Rev_AgePop=x["Rev_AgePop"],
                            Title=title_of(x), Project=x["Project"]))
        elif kind == "AGE":
            out.append(dict(Round2_ID=m["Round2_ID"], Round1_Review_ID=m["Round1_Review_ID"],
                            Stratum=x["Stratum"], Gold_Age=x["Gold_Age"], Round1_Rev_Age=x["Rev_Age"],
                            Title=title_of(x), Project=x["Project"]))
        else:
            out.append(dict(Round2_ID=m["Round2_ID"], Round1_Review_ID=m["Round1_Review_ID"],
                            Stratum=x["Stratum"], Gold_CVD=x["Gold_CVD"], Gold_age_pop=x["Gold_age_pop"],
                            Round1_Rev_CVD=x["Rev_CVD"], Round1_Rev_AgePop=x["Rev_AgePop"],
                            Title=title_of(x), Project=x["Project"]))
    write_table(rk, name, out)

write_map("Map_CHD", "CHD")
write_map("Map_Age", "AGE")
write_map("Map_CVD", "CVD")

key2 = f"{OUT}/chd_manual_recheck_round2_ANSWER_KEY.xlsx"
rk.properties.creator = ""; rk.properties.lastModifiedBy = ""
rk.properties.title = "CHD round-2 ANSWER KEY"
rk.save(key2)
repair_xlsx(key2)
print("wrote", key2)

# Also mirror a short R driver that points at this Python script
with open("R/11_score_review.R", "w") as f:
    f.write('''#' 11_score_review.R — score returned blind review; flag disagreements; build round-2 recheck.
#' Implementation is Python (openpyxl) for robust Excel handling; this driver runs it.
source("R/00_setup.R")
say("Running R/11_score_review.py ...")
rc <- system2("python3", "R/11_score_review.py")
if (!identical(rc, 0L)) stop("11_score_review.py failed with code ", rc)
say("done: outputs/chd_review_scoring.xlsx")
say("done: outputs/chd_manual_recheck_round2_BLIND.xlsx")
say("done: outputs/chd_manual_recheck_round2_ANSWER_KEY.xlsx")
''')

print("\n=== SUMMARY ===")
for row in Summary:
    print(f"{row['Section']:35} | {row['Metric']:55} | {row['Value']}  {row['Note']}")
print(f"\nRound-2 recheck rows: CHD={len(id_chd)} Age={len(id_age)} CVD={len(id_cvd)}")
print("Leak scan hits (excl READ ME):", len(leak_hits))
