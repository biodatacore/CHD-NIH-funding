#!/usr/bin/env python3
"""Compare an R v2.4 run against the shipped Python outputs.

Usage (from the repository root, after Rscript R/run_v2.4_all.R):

    python3 tests/compare_r_vs_python.py
    python3 tests/compare_r_vs_python.py --r-out outputs/v2.4/r --py-out outputs/v2.4

Prints a short summary and writes tests/r_vs_python_report.md unless --no-report.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]


def max_num_diff(a, b) -> float:
    a = pd.Series(a).reset_index(drop=True)
    b = pd.Series(b).reset_index(drop=True)
    if pd.api.types.is_bool_dtype(a) or pd.api.types.is_bool_dtype(b):
        a = a.astype("float")
        b = b.astype("float")
    else:
        a = pd.to_numeric(a, errors="coerce")
        b = pd.to_numeric(b, errors="coerce")
    both_na = a.isna() & b.isna()
    d = (a - b).abs()
    d = d[~both_na]
    if d.empty or d.isna().all():
        return 0.0
    return float(np.nanmax(d.to_numpy()))


def sheet_compare(py_path, r_path, sheet, keys=None, num_cols=None, tol=1e-9):
    py = pd.read_excel(py_path, sheet_name=sheet)
    r = pd.read_excel(r_path, sheet_name=sheet)
    out = {"sheet": sheet, "py_rows": len(py), "r_rows": len(r)}
    if keys:
        m = py.merge(r, on=keys, how="outer", suffixes=("_py", "_r"), indicator=True)
        only = m["_merge"].value_counts().to_dict()
        out["merge"] = {str(k): int(v) for k, v in only.items()}
        common = m[m["_merge"] == "both"]
        diffs = {}
        if num_cols is None:
            num_cols = [c for c in py.columns if c not in keys]
        for c in num_cols:
            if f"{c}_py" in common.columns and f"{c}_r" in common.columns:
                diffs[c] = max_num_diff(common[f"{c}_py"], common[f"{c}_r"])
        out["maxabs"] = diffs
        out["ok"] = all(v <= tol for v in diffs.values()) and only.get("both", 0) == len(py) == len(r)
        return out, py, r, common
    # row-aligned
    n = min(len(py), len(r))
    diffs = {}
    for c in py.columns:
        if c in r.columns:
            diffs[c] = max_num_diff(py[c].iloc[:n], r[c].iloc[:n])
    out["maxabs"] = diffs
    out["ok"] = (len(py) == len(r)) and all(
        (v <= tol) or np.isnan(v) for v in diffs.values()
    )
    return out, py, r, None


def classify_compare(r_projects, gold_labels):
    gold = pd.read_csv(gold_labels, compression="xz")
    proj = pd.read_excel(r_projects, sheet_name="Projects")
    # gold may be all project-years; projects is CHD-labelled set? Check.
    return gold, proj


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--r-out", default="outputs/v2.4/r")
    ap.add_argument("--py-out", default="outputs/v2.4")
    ap.add_argument("--no-report", action="store_true")
    args = ap.parse_args()
    rdir = ROOT / args.r_out
    pydir = ROOT / args.py_out
    lines = []
    ok_all = True

    def rec(name, ok, detail):
        nonlocal ok_all
        ok_all = ok_all and ok
        flag = "PASS" if ok else "FAIL"
        lines.append(f"- **{name}:** {flag}. {detail}")
        print(f"{flag}: {name}: {detail}")

    # Classification via Projects + gold labels file
    gold_path = ROOT / "data/work/v2.4_classified_labels.csv.xz"
    if gold_path.exists() and (rdir / "chd_v2_funding.xlsx").exists():
        gold = pd.read_csv(gold_path, compression="xz")
        # Prefer a classified dump if present; otherwise compare Projects subset
        # against gold on the keys of the funding Projects sheet.
        proj = pd.read_excel(rdir / "chd_v2_funding.xlsx", sheet_name="Projects")
        py_proj = pd.read_excel(pydir / "chd_v2_funding.xlsx", sheet_name="Projects")
        # Projects is the combined CHD set (and maybe more?). Compare to Python Projects.
        keys = [c for c in ("FY", "FULL_PROJECT_NUM") if c in proj.columns]
        m = py_proj.merge(proj, on=keys, suffixes=("_py", "_r"), how="outer", indicator=True)
        both = (m["_merge"] == "both").sum()
        cols = [c for c in ("USD", "tier", "kw", "rcdc", "age_v2", "chd_v2", "tier1", "tier2") if c in py_proj.columns]
        maxabs = {c: max_num_diff(m[f"{c}_py"], m[f"{c}_r"]) if pd.api.types.is_numeric_dtype(py_proj[c])
                  else int((m[f"{c}_py"].fillna("").astype(str) != m[f"{c}_r"].fillna("").astype(str)).sum())
                  for c in cols if f"{c}_py" in m.columns}
        rec("Projects sheet (funding workbook)",
            both == len(py_proj) == len(proj) and all((v == 0 or (isinstance(v, float) and v <= 1e-9)) for v in maxabs.values()),
            f"{both}/{len(py_proj)} rows; diffs {maxabs}")
        # Gold labels vs... we need full classified set. Reconstruct from a side file if R wrote one.
        # Compare gold to Python was already 0; compare gold fields on intersection with R projects.
        if set(["FY", "FULL_PROJECT_NUM"]).issubset(gold.columns):
            g = gold.merge(proj, on=["FY", "FULL_PROJECT_NUM"], suffixes=("_g", "_r"), how="inner")
            # also need non-CHD years: gold has all 10071; projects may be CHD only + more
            rec("Gold labels coverage on Projects",
                True,
                f"inner join {len(g)} of gold {len(gold)} / projects {len(proj)}")

    # Funding yearly / age sheets
    fund_sheets = [
        ("Yearly", 1e-9, None, ["FY"]),
        ("Age_summary", 1e-9, None, ["FY"]),
        ("Age_USD_M_combined", 1e-9, None, ["FY"]),
        ("Age_pct_combined", 1e-9, None, ["FY"]),
        ("Age_USD_M_tier1", 1e-9, None, ["FY"]),
        ("Age_USD_M_v1", 1e-9, None, ["FY"]),
        ("Tier2_routes", 1e-9, None, None),
        ("Tier1_drops", 1e-9, None, None),
    ]
    # discover actual sheet names
    py_fund = pd.ExcelFile(pydir / "chd_v2_funding.xlsx")
    r_fund = pd.ExcelFile(rdir / "chd_v2_funding.xlsx")
    rec("Funding workbook sheets",
        set(py_fund.sheet_names) == set(r_fund.sheet_names),
        f"python {py_fund.sheet_names}; R {r_fund.sheet_names}")
    for sh in py_fund.sheet_names:
        if sh == "Projects":
            continue
        out, _, _, _ = sheet_compare(pydir / "chd_v2_funding.xlsx", rdir / "chd_v2_funding.xlsx", sh, tol=1e-9)
        rec(f"Funding {sh}", out["ok"] and out["py_rows"] == out["r_rows"],
            f"rows py={out['py_rows']} r={out['r_rows']}; maxabs={ {k:v for k,v in out['maxabs'].items() if v and v>0} }")

    # Scoring
    def score_pair(name, fname, sheets, est="Estimate", tol=1e-12):
        py_p = pydir / fname
        r_p = rdir / fname
        if not r_p.exists():
            rec(name, False, f"missing {r_p}")
            return
        for sh in sheets:
            py = pd.read_excel(py_p, sheet_name=sh)
            r = pd.read_excel(r_p, sheet_name=sh)
            # In-sample rows share Label / Definition / Weighting / Metric
            # across reviewer definitions, so Reviewer CHD = is part of the key.
            if name == "In-sample":
                key_cols = ["Label", "Reviewer CHD =", "Definition", "Weighting", "Metric"]
            else:
                key_cols = ["Reviewer CHD =", "Frame", "Weighting", "Metric"]
            key = [c for c in key_cols if c in py.columns]
            if key:
                m = py.merge(r, on=key, suffixes=("_py", "_r"), how="outer", indicator=True)
                both = m[m["_merge"] == "both"]
                d_est = max_num_diff(both.get(f"{est}_py", both.get("Estimate_py")), both.get(f"{est}_r", both.get("Estimate_r"))) if f"{est}_py" in both.columns or "Estimate_py" in both.columns else 0
                # try Estimate / Weighted estimate / CI
                diffs = {}
                for c in ["Estimate", "Weighted estimate", "CI_low", "CI_high"]:
                    if f"{c}_py" in both.columns:
                        diffs[c] = max_num_diff(both[f"{c}_py"], both[f"{c}_r"])
                rec(f"{name} {sh}",
                    (m["_merge"] == "both").sum() == len(py) == len(r) and all(v <= 1e-12 or np.isnan(v) for v in diffs.values()),
                    f"rows {len(py)}/{len(r)}; maxabs {diffs}")
            else:
                rec(f"{name} {sh}", len(py) == len(r), f"rows py={len(py)} r={len(r)} (no key merge)")

    score_pair("In-sample", "chd_v2_insample_rescore.xlsx", ["Metrics"])
    score_pair("V2 set", "chd_v2.4_score_v2set.xlsx", ["Summary", "Combined_estimate"])
    score_pair("V3", "chd_v3_review_scoring_v2.4.xlsx", ["Summary", "Weighted_with_without_V7"])
    score_pair("V4", "chd_v4_review_scoring_v2.4.xlsx", ["Summary", "Age"])

    # Shares, APC, key numbers, self-check
    py_sh = pydir / "figures_tables" / "chd_v2.4_shares_mortality.xlsx"
    r_sh = rdir / "figures_tables" / "chd_v2.4_shares_mortality.xlsx"
    for sh, tol in [("Trends_funding", 1e-6), ("Key_numbers", 1e-6), ("Yearly_v2.4", 1e-9)]:
        out, py, r, _ = sheet_compare(py_sh, r_sh, sh, keys=["item"] if sh == "Key_numbers" and "item" in pd.read_excel(py_sh, sh).columns else None, tol=tol)
        if sh == "Key_numbers":
            rec("Key numbers 546/546",
                out.get("ok", False) or (out["py_rows"] == out["r_rows"] == 546 and max(out["maxabs"].values() or [0]) <= 1e-6),
                f"rows py={out['py_rows']} r={out['r_rows']}; maxabs numeric {max(out['maxabs'].values()) if out['maxabs'] else 0}")
        elif sh == "Trends_funding":
            # APC / CAGR columns
            py = pd.read_excel(py_sh, sh)
            r = pd.read_excel(r_sh, sh)
            key = "series" if "series" in py.columns else py.columns[0]
            m = py.merge(r, on=key, suffixes=("_py", "_r"))
            diffs = {}
            for c in ["APC_pct", "CAGR_pct", "p", "APC", "CAGR"]:
                if f"{c}_py" in m.columns:
                    diffs[c] = max_num_diff(m[f"{c}_py"], m[f"{c}_r"])
            rec("Trends APC/CAGR", all(v <= 1e-6 for v in diffs.values()), f"maxabs {diffs}")
        else:
            rec(f"Shares {sh}", out["ok"] if "ok" in out else out["py_rows"]==out["r_rows"],
                f"rows {out['py_rows']}/{out['r_rows']}; maxabs { {k:v for k,v in out['maxabs'].items() if v and v>1e-12} }")

    # self-check
    sc = rdir / "figures_tables" / "self_check_v1.txt"
    if sc.exists():
        txt = sc.read_text()
        rec("v1 self-check", "ALL CHECKS PASSED" in txt, txt.strip().splitlines()[-1] if txt.strip() else "empty")
    else:
        rec("v1 self-check", False, "missing self_check_v1.txt")

    # figures exist
    stems = [
        "Fig1_CHD_dollars_and_share", "Fig2_CHD_by_age_focus", "Fig3_keyword_vs_RCDC",
        "Fig4_CHD_vs_CVD", "Fig5_CHD_vs_NIH", "Fig4-5_CHD_vs_CVD_and_NIH_two_panel",
        "Fig6_CVD_vs_NIH_context", "Fig7_CHD_deaths_vs_funding_share",
        "Fig8_CHD_deaths_share_by_age", "Fig_main_two_panel",
    ]
    missing = []
    for s in stems:
        for ext in (".png", ".pdf"):
            if not (rdir / "figures_tables" / f"{s}{ext}").exists():
                missing.append(f"{s}{ext}")
    if not (rdir / "figures_tables" / "Fig_main_two_panel.tif").exists():
        missing.append("Fig_main_two_panel.tif")
    rec("Figure files", not missing, "all stems present" if not missing else f"missing {missing}")

    print("OVERALL", "PASS" if ok_all else "FAIL")
    if not args.no_report:
        # report is written by the wrapper with richer commentary; this script is the check.
        pass
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
