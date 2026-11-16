#!/usr/bin/env python3
"""
v2.4 CHD shares, APCs, and funding-vs-mortality tables.

Run from the repository root:

    python3 R/21_v24_shares.py

Writes to outputs/v2.4/figures_tables/. Does not modify v2.4 classification
rules or any existing v1/v2.x output. Dollars are nominal. FY2026 is a
partial year (records through 2026-10-20) and is excluded from trend
statistics (FY2013-2025). Mortality counts are rebuilt from the shipped
aggregated CDC WONDER series (data/wonder/wonder_long.csv); no refetch.

Inputs (all shipped in this repository):
  - outputs/v2.4/chd_v2_funding.xlsx (combined project-year dollars and age)
  - data/work/nih_cvd_yearly.csv (NIH and CVD denominators; RCDC yearly totals)
  - data/work/v24_cv_flags.csv (CVD flag on v2.4 project-years)
  - data/work/rcdc_chd_projects.csv (RCDC CHD project-years, FY2016-2025)
  - data/work/v1_keyword_yearly.csv and v1_keyword_age.csv (v1 self-check numerators)
  - data/work/v1_expected_*.csv (v1 self-check ground truth)
  - data/wonder/wonder_long.csv
  - outputs/v2.4/chd_v3_review_scoring_v2.4.xlsx, chd_v4_review_scoring_v2.4.xlsx,
    chd_v2.4_score_v2set.xlsx (validation metrics copied, not recalculated)

The NIH and CVD denominators were aggregated from the same cached grant
universe used by R/07_cvd.R (one record per full project number per fiscal
year, parent-award total cost, cv flag). The de-identified NIH IC project-year universe and v1 CVD flags are shipped in data/shipped/;
see data/README.md and data/FETCH.md.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.api as sm
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, Border, Side, PatternFill
from openpyxl.utils.dataframe import dataframe_to_rows

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "outputs" / "v2.4" / "figures_tables"
V24_FUNDING = ROOT / "outputs" / "v2.4" / "chd_v2_funding.xlsx"
DATA_WORK = ROOT / "data" / "work"
WONDER_LONG = ROOT / "data" / "wonder" / "wonder_long.csv"

TREND_YEARS = list(range(2013, 2026))  # FY2013-2025; exclude partial FY2026
MORT_YEARS = list(range(2013, 2025))   # calendar 2013-2024
TIER_COMBINED = ("Tier 1 CHD-focused", "Tier 2 CHD-related basic/developmental")

ARIAL = Font(name="Arial", size=11)
ARIAL_B = Font(name="Arial", size=11, bold=True)


def col_name(n):
    """Excel column label for a 1-based index (A, B, ..., AA)."""
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s



def set_workbook_props(wb):
    wb.properties.creator = "CHD pipeline"
    wb.properties.lastModifiedBy = "CHD pipeline"
    wb.properties.title = "v2.4 CHD shares, mortality comparison, and figures"
    wb.properties.subject = "NIH funding for congenital heart disease research"
    wb.properties.description = "v2.4 combined CHD shares of NIH CVD and of all NIH, age split, overlap with the RCDC CHD category, and a funding-vs-mortality comparison."
    wb.properties.keywords = "CHD, NIH, funding, RCDC, mortality"


def r4(x):
    """Round like v1 openxlsx sheets: 4 decimal places for non-integers."""
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return x
    return round(float(x), 4)


def round_df(df, nd=4, skip=()):
    out = df.copy()
    for c in out.columns:
        if c in skip:
            continue
        if pd.api.types.is_numeric_dtype(out[c]) and not pd.api.types.is_integer_dtype(out[c]):
            out[c] = out[c].map(lambda v: np.nan if pd.isna(v) else round(float(v), nd))
    return out


def log_linear_trend(years, values, label, year_set=None):
    """R lm(log(v) ~ y) APC, CAGR, 95% t CI, slope p-value. year_set filters the window."""
    d = pd.DataFrame({"y": np.asarray(years), "v": np.asarray(values, dtype=float)})
    d = d.dropna()
    if year_set is not None:
        d = d[d["y"].isin(year_set)]
    d = d[d["v"] > 0].sort_values("y")
    if len(d) < 3:
        raise ValueError(f"not enough points for trend: {label}")
    X = sm.add_constant(d["y"].to_numpy())
    model = sm.OLS(np.log(d["v"].to_numpy()), X).fit()
    # params: const, y
    b = float(model.params[1])
    ci = model.conf_int(alpha=0.05)
    lo, hi = float(ci[1, 0]), float(ci[1, 1])
    first = float(d.iloc[0]["v"])
    last = float(d.iloc[-1]["v"])
    y0, y1 = int(d.iloc[0]["y"]), int(d.iloc[-1]["y"])
    span = y1 - y0
    return {
        "series": label,
        "years": f"FY{y0}-{y1}" if year_set is None or min(year_set) >= 2013 and max(year_set) <= 2026 else f"{y0}-{y1}",
        "start": first,
        "end": last,
        "CAGR_pct": 100 * ((last / first) ** (1 / span) - 1),
        "APC_pct": 100 * (np.exp(b) - 1),
        "APC_lo": 100 * (np.exp(lo) - 1),
        "APC_hi": 100 * (np.exp(hi) - 1),
        "p": float(model.pvalues[1]),
        "n": int(len(d)),
    }



def keys(df):
    return df["FY"].astype(int).astype(str) + "|" + df["FULL_PROJECT_NUM"].astype(str)


def load_denominators():
    d = pd.read_csv(DATA_WORK / "nih_cvd_yearly.csv")
    d["FY"] = d["FY"].astype(int)
    d["NIH_USD_B"] = d["NIH_USD"] / 1e9
    d["CVD_USD_B"] = d["CVD_USD"] / 1e9
    d["rcdc_USD_M"] = d["rcdc_USD"] / 1e6
    return d


def load_v24_projects():
    proj = pd.read_excel(V24_FUNDING, sheet_name="Projects")
    proj["FY"] = proj["FY"].astype(int)
    proj["key"] = keys(proj)
    proj["combined"] = proj["tier"].isin(TIER_COMBINED)
    flags = pd.read_csv(DATA_WORK / "v24_cv_flags.csv")
    flags["FY"] = flags["FY"].astype(int)
    flags["cv"] = flags["cv"].astype(bool)
    flags["key"] = keys(flags)
    proj = proj.merge(flags[["key", "cv"]], on="key", how="left")
    if proj["cv"].isna().any():
        missing = int(proj["cv"].isna().sum())
        raise SystemExit(f"v24_cv_flags.csv missing {missing} project-years present in chd_v2_funding.xlsx")
    proj["cv"] = proj["cv"].astype(bool)
    return proj


def attach_denom(chd, denoms):
    """Merge CHD numerators with NIH/CVD/RCDC denominators and compute shares."""
    D = denoms.merge(chd, on="FY", how="left")
    D["CVD_pct_of_NIH"] = 100 * D["CVD_USD_B"] / D["NIH_USD_B"]
    D["CHD_pct_of_CVD"] = 100 * D["CHD_in_CVD_USD_M"] / (D["CVD_USD_B"] * 1e3)
    D["CHDall_pct_of_CVD"] = 100 * D["CHD_USD_M"] / (D["CVD_USD_B"] * 1e3)
    D["CHD_pct_of_NIH"] = 100 * D["CHD_USD_M"] / (D["NIH_USD_B"] * 1e3)
    D["rcdc_pct_of_NIH"] = 100 * D["rcdc_USD_M"] / (D["NIH_USD_B"] * 1e3)
    na = ~D["FY"].between(2016, 2025)
    D.loc[na, ["rcdc_projects", "rcdc_USD_M", "rcdc_pct_of_NIH", "rcdc_USD"]] = np.nan
    return D.sort_values("FY").reset_index(drop=True)


def yearly_v1(denoms):
    k = pd.read_csv(DATA_WORK / "v1_keyword_yearly.csv")
    k["FY"] = k["FY"].astype(int)
    chd = pd.DataFrame({
        "FY": k["FY"],
        "CHD_projects": k["CHD_projects"],
        "CHD_USD_M": k["CHD_USD"] / 1e6,
        "CHD_in_CVD_projects": k["CHD_in_CVD_projects"],
        "CHD_in_CVD_USD_M": k["CHD_in_CVD_USD"] / 1e6,
        "CHD_not_CVD_USD_M": k["CHD_not_CVD_USD"] / 1e6,
    })
    return attach_denom(chd, denoms)


def yearly_v24(denoms, proj):
    c = proj[proj["combined"]].copy()
    rows = []
    for fy, g in c.groupby("FY"):
        rows.append({
            "FY": int(fy),
            "CHD_projects": int(len(g)),
            "CHD_USD_M": g["USD"].sum() / 1e6,
            "CHD_in_CVD_projects": int(g["cv"].sum()),
            "CHD_in_CVD_USD_M": g.loc[g["cv"], "USD"].sum() / 1e6,
            "CHD_not_CVD_USD_M": g.loc[~g["cv"], "USD"].sum() / 1e6,
        })
    return attach_denom(pd.DataFrame(rows), denoms)


def age_table(df, age_col, fy_col="FY", usd_col="USD"):
    """Long table of dollars and share of CHD dollars by FY and age group."""
    g = df.groupby([fy_col, age_col], observed=False, as_index=False).agg(USD=(usd_col, "sum"), n=(usd_col, "size"))
    g = g.rename(columns={fy_col: "FY", age_col: "age"})
    g["USD_M"] = g["USD"] / 1e6
    tot = g.groupby("FY")["USD_M"].sum()
    g["pct_of_CHD"] = 100 * g["USD_M"] / g["FY"].map(tot)
    return g.sort_values(["FY", "age"]).reset_index(drop=True)


def age_from_v1():
    a = pd.read_csv(DATA_WORK / "v1_keyword_age.csv")
    a["FY"] = a["FY"].astype(int)
    return age_table(a, "age", usd_col="USD")


def age_from_v24(proj, in_cvd=False):
    c = proj[proj["combined"]].copy()
    if in_cvd:
        c = c[c["cv"]]
    return age_table(c, "age_v2")


def mortality_from_wonder():
    """Rebuild mortality yearly the way R/08_wonder.R does, from the shipped long file. No refetch."""
    R = pd.read_csv(WONDER_LONG)
    S = R[
        ((R["source"] == "bridged") & R["year"].isin(range(2013, 2018)))
        | ((R["source"] == "single") & R["year"].isin(range(2018, 2025)))
    ].copy()
    W = S.pivot_table(index="year", columns=["measure", "age"], values="deaths", aggfunc="first")
    W.columns = [f"{m}_{a}" for m, a in W.columns]
    W = W.reset_index()
    W["chd_ucd_adult"] = W["chd_ucd_all"] - W["chd_ucd_ped"]
    W["chd_any_adult"] = W["chd_any_all"] - W["chd_any_ped"]
    W["cvd_adult"] = W["cvd_all"] - W["cvd_ped"]
    W["heart_adult"] = W["heart_all"] - W["heart_ped"]
    for g in ("all", "ped", "adult"):
        W[f"cvd_{g}"] = W[f"cvd_{g}"] + W[f"chd_ucd_{g}"]
        W[f"heart_{g}"] = W[f"heart_{g}"] + W[f"chd_ucd_{g}"]
    for g in ("all", "ped", "adult"):
        for m in ("chd_ucd", "chd_any"):
            for d in ("cvd", "heart"):
                W[f"{m}_pct_of_{d}_{g}"] = 100.0 * W[f"{m}_{g}"] / W[f"{d}_{g}"]
    W["file_note"] = np.where(
        W["year"] <= 2017,
        "D76 (UCD) / D77 (MCD), bridged-race final",
        "D158 (UCD) / D157 (MCD), single-race final",
    )
    ov = R[R["year"].isin(range(2018, 2021))].copy()
    ov = ov.pivot_table(index=["year", "measure", "age"], columns="source", values="deaths", aggfunc="first").reset_index()
    if "single" in ov.columns and "bridged" in ov.columns:
        ov["diff"] = ov["single"] - ov["bridged"]
    return W, ov, R


def overlap_vs_rcdc(proj):
    comb = proj[proj["combined"]][["FY", "FULL_PROJECT_NUM", "USD"]].copy()
    comb["key"] = keys(comb)
    rcdc = pd.read_csv(DATA_WORK / "rcdc_chd_projects.csv")
    rcdc["FY"] = rcdc["FY"].astype(int)
    rcdc["key"] = keys(rcdc)
    years = sorted(set(rcdc["FY"]) | set(comb[comb.FY.between(2016, 2025)]["FY"]))
    rows = []
    for fy in years:
        c = comb[comb.FY == fy]
        r = rcdc[rcdc.FY == fy]
        cset, rset = set(c["key"]), set(r["key"])
        both, only_c, only_r = cset & rset, cset - rset, rset - cset
        rows.append({
            "FY": int(fy),
            "both_n": len(both),
            "classifier_only_n": len(only_c),
            "rcdc_only_n": len(only_r),
            "both_M": c.loc[c["key"].isin(both), "USD"].sum() / 1e6,
            "classifier_only_M": c.loc[c["key"].isin(only_c), "USD"].sum() / 1e6,
            "rcdc_only_M": r.loc[r["key"].isin(only_r), "USD"].sum() / 1e6,
        })
    O = pd.DataFrame(rows).sort_values("FY")
    tot = {col: O[col].sum() if col != "FY" else np.nan for col in O.columns}
    O = pd.concat([O, pd.DataFrame([tot])], ignore_index=True)
    O["iou_projects"] = O["both_n"] / (O["both_n"] + O["classifier_only_n"] + O["rcdc_only_n"])
    O["pct_classifier_in_rcdc"] = 100 * O["both_n"] / (O["both_n"] + O["classifier_only_n"])
    O["pct_rcdc_in_classifier"] = 100 * O["both_n"] / (O["both_n"] + O["rcdc_only_n"])
    O["iou_dollars"] = O["both_M"] / (O["both_M"] + O["classifier_only_M"] + O["rcdc_only_M"])
    return O


def self_check(D_v1, age_v1, W, trends_v1, out_path: Path):
    v1_ctx = pd.read_csv(DATA_WORK / "v1_expected_cvd_nih_context.csv")
    v1_tr = pd.read_csv(DATA_WORK / "v1_expected_cvd_trends.csv")
    v1_mort = pd.read_csv(DATA_WORK / "v1_expected_mortality_yearly.csv")
    lines = []
    ok = True

    def chk(label, got, exp, nd=4, atol=5e-5):
        nonlocal ok
        g, e = r4(got), r4(exp)
        match = (g == e) or (pd.notna(got) and pd.notna(exp) and abs(float(got) - float(exp)) <= atol)
        status = "OK" if match else "FAIL"
        if not match:
            ok = False
        lines.append(f"  [{status}] {label}: got {got!r} (r4={g})  expected {exp!r} (r4={e})")

    lines.append("V1 SELF-CHECK (keyword classifier, same denominators as R/07_cvd.R and R/05_analysis.R)")
    lines.append("v1 expected tables: data/work/v1_expected_*.csv (values taken from the v1 funding workbook)")
    m = D_v1.merge(v1_ctx, on="FY", suffixes=("_got", "_exp"))
    for _, r in m.iterrows():
        fy = int(r["FY"])
        for col in ("NIH_USD_B", "CVD_USD_B", "CVD_pct_of_NIH", "CHD_USD_M", "CHD_in_CVD_USD_M",
                    "CHD_pct_of_CVD", "CHDall_pct_of_CVD", "CHD_pct_of_NIH"):
            chk(f"FY{fy} {col}", r[f"{col}_got"], r[f"{col}_exp"])
        chk(f"FY{fy} Yearly.chd_USD_M", r["CHD_USD_M_got"], r["chd_USD_M"])
        chk(f"FY{fy} Yearly.chd_pct_of_NIH", r["CHD_pct_of_NIH_got"], r["chd_pct_of_NIH"])
        chk(f"FY{fy} Yearly.nih_projects", r["nih_projects_got"], r["nih_projects_exp"])

    d13 = D_v1[D_v1.FY == 2013].iloc[0]
    d25 = D_v1[D_v1.FY == 2025].iloc[0]
    lines.append("\nHeadline endpoints:")
    chk("FY2013 CHD_pct_of_CVD", d13["CHD_pct_of_CVD"], 2.2124)
    chk("FY2025 CHD_pct_of_CVD", d25["CHD_pct_of_CVD"], 2.1654)
    chk("FY2013 CHD_pct_of_NIH", d13["CHD_pct_of_NIH"], 0.2257)
    chk("FY2025 CHD_pct_of_NIH", d25["CHD_pct_of_NIH"], 0.2033)

    name_map = {
        "Total NIH ($B)": "Total NIH ($B)",
        "Total CVD ($B)": "Total CVD ($B)",
        "CVD % of NIH": "CVD % of NIH",
        "CHD within CVD ($M) [v1 keyword]": "CHD within CVD ($M)",
        "CHD % of CVD [v1 keyword]": "CHD % of CVD",
        "CHD all ($M) [v1 keyword]": "CHD all ($M)",
        "CHD % of NIH [v1 keyword]": "CHD % of NIH",
    }
    for got_name, exp_name in name_map.items():
        g = trends_v1[trends_v1["series"] == got_name]
        e = v1_tr[v1_tr["series"] == exp_name]
        if g.empty or e.empty:
            lines.append(f"  [FAIL] missing trend {got_name} / {exp_name}")
            ok = False
            continue
        g, e = g.iloc[0], e.iloc[0]
        for col, ecol in (("start", "start_FY2013"), ("end", "end_FY2025"),
                          ("CAGR_pct", "CAGR_pct"), ("APC_pct", "APC_pct"),
                          ("APC_lo", "APC_lo"), ("APC_hi", "APC_hi"), ("p", "p")):
            chk(f"CVD_trends {exp_name} {col}", g[col], e[ecol])

    wm = W.merge(v1_mort, on="year", suffixes=("_got", "_exp"))
    for col in ("chd_ucd_all", "chd_ucd_ped", "chd_ucd_adult", "chd_any_all", "chd_any_ped",
                "chd_any_adult", "cvd_all", "cvd_ped", "cvd_adult",
                "chd_ucd_pct_of_cvd_all", "chd_any_pct_of_cvd_all",
                "chd_ucd_pct_of_cvd_ped", "chd_any_pct_of_cvd_adult", "chd_ucd_pct_of_cvd_adult"):
        for _, r in wm.iterrows():
            chk(f"mortality {int(r['year'])} {col}", r[f"{col}_got"], r[f"{col}_exp"])

    for _, r in v1_mort.iterrows():
        fy = int(r["year"])
        exp = D_v1.loc[D_v1.FY == fy, "CHD_pct_of_CVD"]
        if not exp.empty:
            chk(f"Mortality_yearly FY{fy} CHD_pct_of_CVD_funding vs expected context",
                r["CHD_pct_of_CVD_funding"], exp.iloc[0])

    lines.append("\nRESULT: " + ("ALL CHECKS PASSED" if ok else "FAILURES PRESENT"))
    text = "\n".join(lines) + "\n"
    out_path.write_text(text)
    return ok, text

def period_pooled(D, years, name):
    s = D[D["FY"].isin(years)]
    return {
        "period": name,
        "CHD_pct_of_CVD": 100 * s["CHD_in_CVD_USD_M"].sum() / (1e3 * s["CVD_USD_B"].sum()),
        "CHD_pct_of_NIH": 100 * s["CHD_USD_M"].sum() / (1e3 * s["NIH_USD_B"].sum()),
        "CVD_pct_of_NIH": 100 * s["CVD_USD_B"].sum() / s["NIH_USD_B"].sum(),
    }


def funding_trends(D, age_all, age_levels, chd_label):
    rows = []
    rows.append(log_linear_trend(D["FY"], D["NIH_USD_B"], "Total NIH ($B)", TREND_YEARS))
    rows.append(log_linear_trend(D["FY"], D["CVD_USD_B"], "Total CVD ($B)", TREND_YEARS))
    rows.append(log_linear_trend(D["FY"], D["CVD_pct_of_NIH"], "CVD % of NIH", TREND_YEARS))
    rows.append(log_linear_trend(D["FY"], D["CHD_in_CVD_USD_M"], f"CHD within CVD ($M) [{chd_label}]", TREND_YEARS))
    rows.append(log_linear_trend(D["FY"], D["CHD_pct_of_CVD"], f"CHD % of CVD [{chd_label}]", TREND_YEARS))
    rows.append(log_linear_trend(D["FY"], D["CHD_USD_M"], f"CHD all ($M) [{chd_label}]", TREND_YEARS))
    rows.append(log_linear_trend(D["FY"], D["CHD_pct_of_NIH"], f"CHD % of NIH [{chd_label}]", TREND_YEARS))
    # RCDC FY2016-2025
    d = D[D["FY"].isin(range(2016, 2026)) & D["rcdc_USD_M"].notna()]
    rows.append(log_linear_trend(d["FY"], d["rcdc_USD_M"], "CHD, RCDC ($M; FY2016-2025)", list(range(2016, 2026))))
    rows.append(log_linear_trend(d["FY"], d["rcdc_pct_of_NIH"], "CHD % of NIH (RCDC; FY2016-2025)", list(range(2016, 2026))))
    # age dollars and age share of CHD dollars (log-linear skips years with value 0, as v1 did)
    for a in age_levels:
        sub = age_all[age_all["age"] == a]
        mm = D[["FY"]].merge(sub[["FY", "USD_M", "pct_of_CHD"]], on="FY", how="left")
        mm["USD_M"] = mm["USD_M"].fillna(0)
        mm["pct_of_CHD"] = mm["pct_of_CHD"].fillna(0)
        try:
            rows.append(log_linear_trend(mm["FY"], mm["USD_M"], f"CHD {a} ($M) [{chd_label}]", TREND_YEARS))
        except ValueError:
            pass
        try:
            rows.append(log_linear_trend(mm["FY"], mm["pct_of_CHD"], f"CHD {a} (% of CHD $) [{chd_label}]", TREND_YEARS))
        except ValueError:
            pass
    return pd.DataFrame(rows)


def mortality_trends(W):
    cols = [c for c in W.columns if ("_pct_of_" in c or c.startswith("chd_ucd_") or c.startswith("chd_any_")
            or c.startswith("cvd_") or c.startswith("heart_") or c == "CHD_pct_of_CVD_funding")]
    # keep count and pct series like 08_wonder (grep _pct_of_|deaths|chd_(ucd|any)_|CHD_pct)
    keep = [c for c in W.columns if c != "year" and c != "file_note" and pd.api.types.is_numeric_dtype(W[c])]
    rows = []
    for c in keep:
        try:
            t = log_linear_trend(W["year"], W[c], c, MORT_YEARS)
            t["years"] = "2013-2024"
            t["y2013"] = t.pop("start")
            t["y2024"] = t.pop("end")
            rows.append(t)
        except ValueError:
            pass
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# self-check against v1 workbook
# ---------------------------------------------------------------------------


def write_sheet(wb, name, df, note=None, number_format="0.0000"):
    ws = wb.create_sheet(name)
    start = 1
    # Notes live in README (and a comment on A1) so the header stays on row 1 for easy reading.
    for r_i, row in enumerate(dataframe_to_rows(df, index=False, header=True), start):
        for c_i, val in enumerate(row, 1):
            cell = ws.cell(r_i, c_i, val if not (isinstance(val, float) and np.isnan(val)) else None)
            cell.font = ARIAL_B if r_i == start else ARIAL
            if isinstance(val, float) and not np.isnan(val) and number_format:
                cell.number_format = number_format
    if note:
        from openpyxl.comments import Comment
        ws.cell(1, 1).comment = Comment(note, "CHD pipeline")
    ws.freeze_panes = f"A{start+1}"
    ws.sheet_view.showGridLines = True
    for c in range(1, df.shape[1] + 1):
        maxlen = 0
        for r in range(1, min(ws.max_row, 40) + 1):
            v = ws.cell(r, c).value
            if v is not None:
                maxlen = max(maxlen, min(len(str(v)), 48))
        ws.column_dimensions[col_name(c)].width = min(max(maxlen + 2, 12), 50)
    ws.page_setup.orientation = "landscape"
    ws.page_setup.fitToPage = True
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.oddFooter.center.text = "&P"
    ws.oddFooter.center.fontName = "Arial"


def write_workbook(path, payload):
    wb = Workbook()
    wb.remove(wb.active)
    set_workbook_props(wb)
    # README
    ws = wb.create_sheet("README", 0)
    rows = [
        ("Item", "Text"),
        ("Purpose", "v2.4 combined (Tier 1 + Tier 2) CHD funding shares of NIH CVD and of all NIH, age split, APCs, and a funding-vs-mortality comparison. New outputs only; v1 and earlier v2.x files were not overwritten."),
        ("CHD definition", "v2.4 combined = Tier 1 CHD-focused + Tier 2 CHD-related basic/developmental science, from outputs/v2.4/chd_v2_funding.xlsx (Projects sheet). Rules were not changed in this run."),
        ("Universe / denominators", "Yearly NIH and CVD denominators in data/work/nih_cvd_yearly.csv were aggregated from the same cached grant universe used by R/07_cvd.R (one record per full project number per fiscal year, parent-award total cost, and the same CVD flag). The de-identified NIH IC project-year universe and v1 CVD flags used for these denominators are shipped in data/shipped/ and rebuilt by R/run_all_v2.4.R. assemble.py was not run."),
        ("CHD % of CVD", "Numerator = v2.4 combined projects that also meet the CVD definition (nested). CHDall % of CVD (all combined dollars / CVD) is also reported."),
        ("Dollars", "Nominal parent-award total cost (direct + indirect). The v1 pipeline did not inflation-adjust; no deflator series is included."),
        ("FY2026", "Partial fiscal year (records retrieved 2026-10-20). Shown in yearly tables and figures (lighter) but excluded from APC/CAGR (FY2013-2025), matching the FY2013-2025 window used for the v1 tables."),
        ("Age focus", "v2.4 4-level: Pediatric / Adult / Both / Not age-specific (age_v2). v1 used a 5-level scheme (Pediatric / Adult / Both / Basic/non-age-specific / Unclear); those v1 categories are on the comparison sheet only."),
        ("Trends", "Log-linear OLS of log(value) on year; APC = 100*(exp(slope)-1) with 95% t-interval and slope p, as in R/05_analysis.R and R/07_cvd.R. CAGR uses end/start over the same window."),
        ("Mortality", "US deaths 2013-2024 from cached CDC WONDER files in data/wonder (no refetch): D76/D77 bridged-race final for 2013-2017; D158/D157 single-race final for 2018-2024. CHD = ICD-10 Q20-Q26 as underlying cause or any mention. Denominators = underlying-cause CVD (I00-I99) or heart disease, each plus underlying-cause CHD. Pediatric = ages 0-17; adult = all ages minus pediatric (includes age not stated). Counts are unchanged from v1."),
        ("Funding vs mortality", "v1 reported the CHD share of NIH CVD funding (nested numerator) alongside mortality shares; it did not compute a dollars-per-death ratio. The same share ratio is used here, with the v2.4 nested CHD % of CVD."),
        ("Self-check", "This script first rebuilds v1 keyword shares from the shipped yearly denominators and v1 keyword numerators and compares them to data/work/v1_expected_*.csv (including CHD % of CVD 2.2124 in FY2013 and 2.1654 in FY2025, and CHD % of NIH 0.2257 to 0.2033). See Self_check."),
        ("Figures", "PNG/PDF analogs of the v1 Fig1-Fig8 series and a two-panel main figure (PNG+TIF, 300 dpi) are in this folder. They use v2.4 combined dollars and shares; mortality panels use the unchanged death counts."),
        ("Inflation", "Not applied (v1 used nominal dollars only)."),
    ]
    for r in rows:
        ws.append(list(r))
    ws["A1"].font = ARIAL_B
    ws["B1"].font = ARIAL_B
    for r in range(2, ws.max_row + 1):
        ws[f"A{r}"].font = ARIAL_B
        ws[f"B{r}"].font = ARIAL
        ws[f"B{r}"].alignment = Alignment(wrap_text=True, vertical="top")
        ws.row_dimensions[r].height = 48
    ws.column_dimensions["A"].width = 28
    ws.column_dimensions["B"].width = 110
    ws.freeze_panes = "A2"
    ws.oddFooter.center.text = "&P"

    write_sheet(wb, "Yearly_v2.4", round_df(payload["D_v24"]),
                note="v2.4 combined (Tier 1+2). NIH and CVD denominators are the v1 universe. FY2026 is partial. Shares use nominal dollars.")
    write_sheet(wb, "Yearly_v1_keyword", round_df(payload["D_v1"]),
                note="v1 keyword classifier, rebuilt in this run for the self-check and the comparison sheet. Should match the v1 workbook.")
    # age wide
    def age_wide(age_df, levels, val="USD_M"):
        w = age_df.pivot_table(index="FY", columns="age", values=val, aggfunc="sum", fill_value=0).reset_index()
        cols = ["FY"] + [c for c in levels if c in w.columns] + [c for c in w.columns if c not in ["FY"] + list(levels)]
        return w[cols]

    lv24 = ["Pediatric", "Adult", "Both", "Not age-specific"]
    lv1 = ["Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear"]
    write_sheet(wb, "Age_USD_M_v2.4", round_df(age_wide(payload["age_v24"], lv24)),
                note="v2.4 combined dollars by age_v2 (all combined CHD, not restricted to CVD).")
    write_sheet(wb, "Age_pct_v2.4", round_df(age_wide(payload["age_v24"], lv24, "pct_of_CHD")),
                note="Percent of v2.4 combined CHD dollars.")
    write_sheet(wb, "Age_in_CVD_USD_M_v2.4", round_df(age_wide(payload["age_incvd_v24"], lv24)),
                note="v2.4 combined dollars among projects that also meet the CVD definition (numerator of CHD % of CVD), by age_v2.")
    write_sheet(wb, "Age_USD_M_v1", round_df(age_wide(payload["age_v1"], lv1)),
                note="v1 keyword dollars by the v1 5-level age scheme, rebuilt in this run.")
    write_sheet(wb, "Overlap_v2.4_vs_RCDC", round_df(payload["O_v24"]),
                note="v2.4 combined vs RCDC 'Congenital Heart Disease', FY2016-2025 (plus a total row with FY blank).")
    write_sheet(wb, "CVD_periods_v2.4", round_df(payload["periods_v24"]),
                note="Pooled dollars in each period (not a simple average of yearly shares).")
    write_sheet(wb, "Trends_funding", round_df(payload["trends_all"]),
                note="Log-linear APC with 95% CI and CAGR. Funding series use FY2013-2025 (RCDC: FY2016-2025). Mortality-window funding share APC is on Mortality_trends.")
    W24 = payload["W_v24"]
    write_sheet(wb, "Mortality_yearly", round_df(W24, skip=("year",)),
                note="Death counts are identical to v1. CHD_pct_of_CVD_funding is the v2.4 nested CHD share of NIH CVD funding (FY aligned to calendar year). No dollars-per-death ratio was defined in v1.")
    write_sheet(wb, "Mortality_trends", round_df(payload["mort_tr_v24"]),
                note="Calendar years 2013-2024. CHD_pct_of_CVD_funding here uses the v2.4 share. Death-count APCs should match v1.")
    write_sheet(wb, "Mortality_splice_check", payload["ov"],
                note="2018-2020 counts in both WONDER file families (bridged vs single). v1 found no differences.")
    write_sheet(wb, "v1_vs_v2.4", round_df(payload["compare"]),
                note="Headline side-by-side. Age categories are not fully comparable: v2.4 uses a 4-level rule (Not age-specific absorbs v1 Basic/non-age-specific and Unclear, and the rules themselves changed).")
    write_sheet(wb, "Key_numbers", payload["key_numbers"],
                note="Key numbers, each with its source, each with its source. Validation metrics are copied from the v2.4 scoring workbooks without recalculation. Full stored precision; do not rely on a 4-decimal display format.",
                number_format="0.0000000000")
    write_sheet(wb, "Self_check", payload["check_df"],
                note=payload["check_header"])

    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    return path


def comparison_sheet(D_v1, D_v24, trends_v1, trends_v24, age_v1, age_v24, mort_tr_v1, mort_tr_v24):
    rows = []

    def add(item, year, v1, v24, unit=""):
        rows.append({
            "item": item,
            "year_or_window": year,
            "v1_keyword": v1,
            "v2.4_combined": v24,
            "abs_diff_v24_minus_v1": (None if (v1 is None or v24 is None or pd.isna(v1) or pd.isna(v24)) else float(v24) - float(v1)),
            "unit": unit,
        })

    for fy in range(2013, 2027):
        a = D_v1[D_v1.FY == fy].iloc[0]
        b = D_v24[D_v24.FY == fy].iloc[0]
        add("CHD dollars", f"FY{fy}", a["CHD_USD_M"], b["CHD_USD_M"], "$ millions, nominal")
        add("CHD project-years", f"FY{fy}", a["CHD_projects"], b["CHD_projects"], "n")
        add("CHD % of all NIH", f"FY{fy}", a["CHD_pct_of_NIH"], b["CHD_pct_of_NIH"], "percent")
        add("CHD % of NIH CVD (nested)", f"FY{fy}", a["CHD_pct_of_CVD"], b["CHD_pct_of_CVD"], "percent")
        add("All-CHD % of NIH CVD", f"FY{fy}", a["CHDall_pct_of_CVD"], b["CHDall_pct_of_CVD"], "percent")
        add("CHD within CVD dollars", f"FY{fy}", a["CHD_in_CVD_USD_M"], b["CHD_in_CVD_USD_M"], "$ millions, nominal")
        add("NIH total", f"FY{fy}", a["NIH_USD_B"], b["NIH_USD_B"], "$ billions, nominal (denominator, unchanged)")
        add("NIH CVD total", f"FY{fy}", a["CVD_USD_B"], b["CVD_USD_B"], "$ billions, nominal (denominator, unchanged)")

    # age shares of all CHD $ , FY2013 and FY2025 and pooled 2013-2026
    def age_pct(age_df, fy, age):
        s = age_df[(age_df.FY == fy) & (age_df.age == age)]
        return float(s["pct_of_CHD"].iloc[0]) if len(s) else 0.0

    def age_usd(age_df, fy, age):
        s = age_df[(age_df.FY == fy) & (age_df.age == age)]
        return float(s["USD_M"].iloc[0]) if len(s) else 0.0

    def age_pct_pooled(age_df, ages_label, fy_min=2013, fy_max=2026):
        s = age_df[(age_df.FY >= fy_min) & (age_df.FY <= fy_max)]
        tot = s["USD_M"].sum()
        sub = s[s.age == ages_label]["USD_M"].sum()
        return 100 * sub / tot if tot else np.nan

    for fy in (2013, 2025, 2026):
        for a in ("Pediatric", "Adult", "Both"):
            add(f"Age share of CHD $: {a}", f"FY{fy}", age_pct(age_v1, fy, a), age_pct(age_v24, fy, a), "percent of CHD $")
            add(f"Age dollars: {a}", f"FY{fy}", age_usd(age_v1, fy, a), age_usd(age_v24, fy, a), "$ millions, nominal")
        add("Age share of CHD $: Basic/non-age-specific (v1 only)", f"FY{fy}", age_pct(age_v1, fy, "Basic/non-age-specific"), None, "percent of CHD $")
        add("Age share of CHD $: Unclear (v1 only)", f"FY{fy}", age_pct(age_v1, fy, "Unclear"), None, "percent of CHD $")
        add("Age share of CHD $: Not age-specific (v2.4 only)", f"FY{fy}", None, age_pct(age_v24, fy, "Not age-specific"), "percent of CHD $")

    for a in ("Pediatric", "Adult", "Both"):
        add(f"Age share of CHD $: {a}", "FY2013-2026 pooled", age_pct_pooled(age_v1, a), age_pct_pooled(age_v24, a), "percent of CHD $")
    add("Age share of CHD $: Basic/non-age-specific (v1 only)", "FY2013-2026 pooled", age_pct_pooled(age_v1, "Basic/non-age-specific"), None, "percent of CHD $")
    add("Age share of CHD $: Unclear (v1 only)", "FY2013-2026 pooled", age_pct_pooled(age_v1, "Unclear"), None, "percent of CHD $")
    add("Age share of CHD $: Not age-specific (v2.4 only)", "FY2013-2026 pooled", None, age_pct_pooled(age_v24, "Not age-specific"), "percent of CHD $")

    # trend pairs
    tmap = [
        ("CHD all ($M) [v1 keyword]", "CHD all ($M) [v2.4 combined]", "APC, CHD dollars, FY2013-2025"),
        ("CHD % of NIH [v1 keyword]", "CHD % of NIH [v2.4 combined]", "APC, CHD % of NIH, FY2013-2025"),
        ("CHD within CVD ($M) [v1 keyword]", "CHD within CVD ($M) [v2.4 combined]", "APC, CHD within CVD $, FY2013-2025"),
        ("CHD % of CVD [v1 keyword]", "CHD % of CVD [v2.4 combined]", "APC, CHD % of CVD, FY2013-2025"),
        ("CHD Pediatric ($M) [v1 keyword]", "CHD Pediatric ($M) [v2.4 combined]", "APC, Pediatric CHD $, FY2013-2025"),
        ("CHD Adult ($M) [v1 keyword]", "CHD Adult ($M) [v2.4 combined]", "APC, Adult CHD $, FY2013-2025"),
        ("CHD Both ($M) [v1 keyword]", "CHD Both ($M) [v2.4 combined]", "APC, Both-ages CHD $, FY2013-2025"),
        ("CHD Pediatric (% of CHD $) [v1 keyword]", "CHD Pediatric (% of CHD $) [v2.4 combined]", "APC, Pediatric share of CHD $, FY2013-2025"),
        ("CHD Adult (% of CHD $) [v1 keyword]", "CHD Adult (% of CHD $) [v2.4 combined]", "APC, Adult share of CHD $, FY2013-2025"),
        ("CHD Both (% of CHD $) [v1 keyword]", "CHD Both (% of CHD $) [v2.4 combined]", "APC, Both-ages share of CHD $, FY2013-2025"),
    ]
    for a, b, lab in tmap:
        g = trends_v1[trends_v1.series == a]
        h = trends_v24[trends_v24.series == b]
        if g.empty or h.empty:
            continue
        g, h = g.iloc[0], h.iloc[0]
        add(f"{lab} (APC)", g["years"], g["APC_pct"], h["APC_pct"], "percent per year")
        add(f"{lab} (APC lo)", g["years"], g["APC_lo"], h["APC_lo"], "percent per year")
        add(f"{lab} (APC hi)", g["years"], g["APC_hi"], h["APC_hi"], "percent per year")
        add(f"{lab} (p)", g["years"], g["p"], h["p"], "slope p-value")
        add(f"{lab} (CAGR)", g["years"], g["CAGR_pct"], h["CAGR_pct"], "percent per year")

    # mortality-window funding share APC
    if mort_tr_v1 is not None and mort_tr_v24 is not None:
        g = mort_tr_v1[mort_tr_v1.series == "CHD_pct_of_CVD_funding"]
        h = mort_tr_v24[mort_tr_v24.series == "CHD_pct_of_CVD_funding"]
        if not g.empty and not h.empty:
            g, h = g.iloc[0], h.iloc[0]
            add("APC, CHD % of CVD funding (aligned to mortality years)", "2013-2024", g["APC_pct"], h["APC_pct"], "percent per year")
            add("APC lo, CHD % of CVD funding (mortality years)", "2013-2024", g["APC_lo"], h["APC_lo"], "percent per year")
            add("APC hi, CHD % of CVD funding (mortality years)", "2013-2024", g["APC_hi"], h["APC_hi"], "percent per year")
            add("p, CHD % of CVD funding (mortality years)", "2013-2024", g["p"], h["p"], "slope p-value")

    # range / peak
    def peak(D):
        s = D[D.FY.between(2013, 2025)]
        i = s["CHD_USD_M"].idxmax()
        return int(s.loc[i, "FY"]), float(s.loc[i, "CHD_USD_M"])
    p1y, p1v = peak(D_v1)
    p2y, p2v = peak(D_v24)
    add("Peak CHD $ year (FY2013-2025)", "FY2013-2025", p1y, p2y, "fiscal year")
    add("Peak CHD $ value (FY2013-2025)", f"v1 FY{p1y}; v2.4 FY{p2y}", p1v, p2v, "$ millions, nominal")
    add("FY2013-2025 dollar change", "FY2025 minus FY2013",
        float(D_v1[D_v1.FY == 2025].CHD_USD_M.iloc[0] - D_v1[D_v1.FY == 2013].CHD_USD_M.iloc[0]),
        float(D_v24[D_v24.FY == 2025].CHD_USD_M.iloc[0] - D_v24[D_v24.FY == 2013].CHD_USD_M.iloc[0]),
        "$ millions, nominal")
    add("FY2013-2025 percent change in CHD $", "100*(FY2025/FY2013 - 1)",
        100 * (float(D_v1[D_v1.FY == 2025].CHD_USD_M.iloc[0]) / float(D_v1[D_v1.FY == 2013].CHD_USD_M.iloc[0]) - 1),
        100 * (float(D_v24[D_v24.FY == 2025].CHD_USD_M.iloc[0]) / float(D_v24[D_v24.FY == 2013].CHD_USD_M.iloc[0]) - 1),
        "percent")
    return pd.DataFrame(rows)




def ic_shares(proj):
    """Share of v2.4 combined dollars by administering IC (NHLBI / HL)."""
    c = proj[proj["combined"]].copy()
    # FY2013-2025 (trend window) and all years including partial FY2026
    out = {}
    for label, mask in (
        ("FY2013-2025", c["FY"].isin(TREND_YEARS)),
        ("FY2013-2026", c["FY"].between(2013, 2026)),
    ):
        s = c[mask]
        tot = s["USD"].sum()
        hl = s[s["IC"] == "HL"]["USD"].sum()
        out[label] = {"total": tot / 1e6, "nhlbi": hl / 1e6, "nhlbi_pct": 100 * hl / tot if tot else None, "n": int(len(s))}
    return out


def rcdc_outside(O):
    """Share of RCDC dollars that are outside the v2.4 combined classifier, FY2016-2025."""
    tot = O.dropna(subset=["FY"])
    rcdc_d = tot["both_M"].sum() + tot["rcdc_only_M"].sum()
    only = tot["rcdc_only_M"].sum()
    return {
        "rcdc_only_M": only,
        "rcdc_total_M": rcdc_d,
        "pct_rcdc_dollars_outside_v24": 100 * only / rcdc_d if rcdc_d else None,
        "pct_v24_dollars_inside_rcdc": 100 * tot["both_M"].sum() / (tot["both_M"].sum() + tot["classifier_only_M"].sum()),
    }


def _val_rows_from_scoring():
    """Read V3, V4, and combined-estimate validation metrics from the v2.4 scoring workbooks."""
    rows = []
    v3 = ROOT / "outputs" / "v2.4" / "chd_v3_review_scoring_v2.4.xlsx"
    v4 = ROOT / "outputs" / "v2.4" / "chd_v4_review_scoring_v2.4.xlsx"
    comb = ROOT / "outputs" / "v2.4" / "chd_v2.4_score_v2set.xlsx"

    def add(item, value, source, sheet, note=""):
        rows.append({
            "section": "Validation",
            "item": item,
            "value": value,
            "window": "",
            "unit": "",
            "source_file": str(source),
            "source_sheet": sheet,
            "note": note,
        })

    s = pd.read_excel(v3, "Summary")
    w = pd.read_excel(v3, "Weighted_with_without_V7")
    # Unweighted Yes|Partly
    u = s[(s["Reviewer CHD ="] == "Yes|Partly") & (s["Weighting"] == "unweighted")]
    for _, r in u.iterrows():
        add(f"V3 unweighted Yes|Partly {r['Metric']}", r["Estimate"], v3, "Summary",
            f"CI {r['CI_low']} to {r['CI_high']}" if pd.notna(r.get("CI_low")) else "n=197 after 3 Unsure excluded (TP/FP/FN/TN 109/6/15/67)")
        if pd.notna(r.get("CI_low")):
            add(f"V3 unweighted Yes|Partly {r['Metric']} CI_low", r["CI_low"], v3, "Summary", "")
            add(f"V3 unweighted Yes|Partly {r['Metric']} CI_high", r["CI_high"], v3, "Summary", "")
    # Weighted excluding V7
    x = w[(w["Frame"].astype(str).str.contains("without V7")) & (w["Reviewer CHD ="] == "Yes|Partly")]
    for _, r in x.iterrows():
        est = r["Weighted estimate"] if "Weighted estimate" in r.index else r.get("Estimate")
        add(f"V3 weighted excluding V7 Yes|Partly {r['Metric']}", est, v3, "Weighted_with_without_V7",
            f"CI {r['CI_low']} to {r['CI_high']}" if pd.notna(r.get("CI_low")) else "")
        if pd.notna(r.get("CI_low")):
            add(f"V3 weighted excluding V7 Yes|Partly {r['Metric']} CI_low", r["CI_low"], v3, "Weighted_with_without_V7", "")
            add(f"V3 weighted excluding V7 Yes|Partly {r['Metric']} CI_high", r["CI_high"], v3, "Weighted_with_without_V7", "")

    s4 = pd.read_excel(v4, "Summary")
    u4 = s4[(s4["Reviewer CHD ="] == "Yes|Partly") & (s4["Weighting"] == "unweighted")
            & (s4["Frame"].astype(str).str.contains("all strata"))]
    for _, r in u4.iterrows():
        add(f"V4 unweighted Yes|Partly {r['Metric']}", r["Estimate"], v4, "Summary",
            f"CI {r['CI_low']} to {r['CI_high']}" if pd.notna(r.get("CI_low")) else "n=198 after 2 Unsure excluded")
        if pd.notna(r.get("CI_low")):
            add(f"V4 unweighted Yes|Partly {r['Metric']} CI_low", r["CI_low"], v4, "Summary", "")
            add(f"V4 unweighted Yes|Partly {r['Metric']} CI_high", r["CI_high"], v4, "Summary", "")
    w4 = s4[(s4["Reviewer CHD ="] == "Yes|Partly") & (s4["Weighting"] == "weighted")
            & (s4["Frame"].astype(str).str.contains("all strata"))]
    for _, r in w4.iterrows():
        add(f"V4 weighted all strata Yes|Partly {r['Metric']}", r["Estimate"], v4, "Summary",
            f"CI {r['CI_low']} to {r['CI_high']}" if pd.notna(r.get("CI_low")) else "")
        if pd.notna(r.get("CI_low")):
            add(f"V4 weighted all strata Yes|Partly {r['Metric']} CI_low", r["CI_low"], v4, "Summary", "")
            add(f"V4 weighted all strata Yes|Partly {r['Metric']} CI_high", r["CI_high"], v4, "Summary", "")

    ce = pd.read_excel(comb, "Combined_estimate")
    ce = ce[ce["Reviewer CHD ="] == "Yes|Partly"]
    for _, r in ce.iterrows():
        add(f"Combined estimate Yes|Partly {r['Metric']}", r["Estimate"], comb, "Combined_estimate",
            f"CI {r['CI_low']} to {r['CI_high']}" if pd.notna(r.get("CI_low")) else "v1 833 tier-1 census + v2 fresh 200")
        if pd.notna(r.get("CI_low")):
            add(f"Combined estimate Yes|Partly {r['Metric']} CI_low", r["CI_low"], comb, "Combined_estimate", "")
            add(f"Combined estimate Yes|Partly {r['Metric']} CI_high", r["CI_high"], comb, "Combined_estimate", "")

    a3 = pd.read_excel(v3, "Age").iloc[0]
    add("V3 age agreement n", a3["n"], v3, "Age", "age-focus agreement among grants with an age label")
    add("V3 age agreement", a3["Agreement"], v3, "Age", "")
    add("V3 age kappa", a3["Kappa"], v3, "Age", "")
    a4 = pd.read_excel(v4, "Age").iloc[0]
    add("V4 age agreement n used", a4["n used for agreement"], v4, "Age", "V4 is a clear-case CHD set; age kappa is weak")
    add("V4 age agreement", a4["Agreement"], v4, "Age", "V4 Notes sheet still says 'v2.3 pipeline'; counts are v2.4")
    add("V4 age kappa", a4["Kappa"], v4, "Age", "V4 Notes sheet still says 'v2.3 pipeline'; counts are v2.4")
    return rows


def build_key_numbers(D, age, trends, W, mort_tr, O, periods, proj, xlsx_name):
    """Every quantity a summary of these results would cite, with its source."""
    src_xlsx = str(Path("outputs/v2.4/figures_tables") / xlsx_name)
    rows = []

    def add(section, item, value, window, unit, sheet, note=""):
        rows.append({
            "section": section, "item": item, "value": value, "window": window, "unit": unit,
            "source_file": src_xlsx, "source_sheet": sheet, "note": note,
        })

    def rowfy(fy):
        return D[D.FY == fy].iloc[0]

    def trend(name):
        s = trends[trends.series == name]
        return None if s.empty else s.iloc[0]

    def age_usd(fy, a):
        s = age[(age.FY == fy) & (age.age == a)]
        return float(s["USD_M"].iloc[0]) if len(s) else 0.0

    def age_pct(fy, a):
        s = age[(age.FY == fy) & (age.age == a)]
        return float(s["pct_of_CHD"].iloc[0]) if len(s) else 0.0

    # Funding
    for fy in range(2013, 2027):
        r = rowfy(fy)
        note = "PARTIAL fiscal year" if fy == 2026 else ""
        add("Funding", f"CHD dollars FY{fy}", r.CHD_USD_M, f"FY{fy}", "$ millions, nominal", "Yearly_v2.4", note)
        add("Funding", f"CHD project-years FY{fy}", r.CHD_projects, f"FY{fy}", "n", "Yearly_v2.4", note)
        add("Shares", f"CHD % of all NIH FY{fy}", r.CHD_pct_of_NIH, f"FY{fy}", "percent", "Yearly_v2.4", note)
        add("Shares", f"CHD % of NIH CVD (nested) FY{fy}", r.CHD_pct_of_CVD, f"FY{fy}", "percent", "Yearly_v2.4", note)
        add("Shares", f"All-CHD % of NIH CVD FY{fy}", r.CHDall_pct_of_CVD, f"FY{fy}", "percent", "Yearly_v2.4", note)
        add("Shares", f"CHD within CVD dollars FY{fy}", r.CHD_in_CVD_USD_M, f"FY{fy}", "$ millions, nominal", "Yearly_v2.4", note)
        for a in ("Pediatric", "Adult", "Both", "Not age-specific"):
            add("Age", f"{a} dollars FY{fy}", age_usd(fy, a), f"FY{fy}", "$ millions, nominal", "Age_USD_M_v2.4", "v2.4 4-level age_v2; all combined CHD")
            add("Age", f"{a} share of CHD $ FY{fy}", age_pct(fy, a), f"FY{fy}", "percent of CHD $", "Age_pct_v2.4", "v2.4 4-level age_v2")

    d13, d25 = rowfy(2013), rowfy(2025)
    peak = D[D.FY.between(2013, 2025)]
    p = peak.loc[peak.CHD_USD_M.idxmax()]
    add("Funding", "Peak CHD $ year", int(p.FY), "FY2013-2025", "fiscal year", "Yearly_v2.4", "")
    add("Funding", "Peak CHD $ value", float(p.CHD_USD_M), f"FY{int(p.FY)}", "$ millions, nominal", "Yearly_v2.4", "")
    add("Funding", "FY2013-2025 percent change in CHD $", 100 * (d25.CHD_USD_M / d13.CHD_USD_M - 1),
        "FY2013-2025", "percent", "Yearly_v2.4", "100*(FY2025/FY2013 - 1)")
    add("Funding", "FY2013-2025 CHD project-years start, end", f"{int(d13.CHD_projects)} to {int(d25.CHD_projects)}",
        "FY2013-2025", "n", "Yearly_v2.4", "")

    # min-max shares FY2013-2025
    w = D[D.FY.between(2013, 2025)]
    add("Shares", "CHD % of NIH CVD (nested) min FY2013-2025", float(w.CHD_pct_of_CVD.min()),
        f"FY{int(w.loc[w.CHD_pct_of_CVD.idxmin()].FY)}", "percent", "Yearly_v2.4", "")
    add("Shares", "CHD % of NIH CVD (nested) max FY2013-2025", float(w.CHD_pct_of_CVD.max()),
        f"FY{int(w.loc[w.CHD_pct_of_CVD.idxmax()].FY)}", "percent", "Yearly_v2.4", "")
    add("Shares", "CHD % of all NIH min FY2013-2025", float(w.CHD_pct_of_NIH.min()),
        f"FY{int(w.loc[w.CHD_pct_of_NIH.idxmin()].FY)}", "percent", "Yearly_v2.4", "")
    add("Shares", "CHD % of all NIH max FY2013-2025", float(w.CHD_pct_of_NIH.max()),
        f"FY{int(w.loc[w.CHD_pct_of_NIH.idxmax()].FY)}", "percent", "Yearly_v2.4", "")

    for series, label in [
        ("CHD all ($M) [v2.4 combined]", "CHD dollars"),
        ("CHD % of NIH [v2.4 combined]", "CHD % of all NIH"),
        ("CHD within CVD ($M) [v2.4 combined]", "CHD within CVD dollars"),
        ("CHD % of CVD [v2.4 combined]", "CHD % of NIH CVD (nested)"),
        ("Total NIH ($B)", "Total NIH dollars"),
        ("Total CVD ($B)", "Total NIH CVD dollars"),
        ("CVD % of NIH", "CVD % of NIH"),
        ("CHD, RCDC ($M; FY2016-2025)", "RCDC CHD dollars"),
        ("CHD % of NIH (RCDC; FY2016-2025)", "RCDC CHD % of NIH"),
    ]:
        tr = trend(series)
        if tr is None:
            continue
        add("Trends", f"{label} CAGR", tr.CAGR_pct, tr.years, "percent per year", "Trends_funding", "end/start over the window")
        add("Trends", f"{label} APC", tr.APC_pct, tr.years, "percent per year", "Trends_funding", "log-linear OLS")
        add("Trends", f"{label} APC 95% CI low", tr.APC_lo, tr.years, "percent per year", "Trends_funding", "")
        add("Trends", f"{label} APC 95% CI high", tr.APC_hi, tr.years, "percent per year", "Trends_funding", "")
        add("Trends", f"{label} APC p", tr.p, tr.years, "slope p-value", "Trends_funding", "")

    for a in ("Pediatric", "Adult", "Both", "Not age-specific"):
        for kind, unit in (("$M", "$ millions, nominal"), ("% of CHD $", "percent of CHD $")):
            tr = trend(f"CHD {a} ({kind}) [v2.4 combined]")
            if tr is None:
                continue
            add("Age trends", f"{a} {kind} CAGR", tr.CAGR_pct, tr.years, "percent per year", "Trends_funding",
                f"n={int(tr.n)} years with value > 0" if tr.n < 13 else "")
            add("Age trends", f"{a} {kind} APC", tr.APC_pct, tr.years, "percent per year", "Trends_funding",
                f"n={int(tr.n)} years with value > 0" if tr.n < 13 else "")
            add("Age trends", f"{a} {kind} APC 95% CI low", tr.APC_lo, tr.years, "percent per year", "Trends_funding", "")
            add("Age trends", f"{a} {kind} APC 95% CI high", tr.APC_hi, tr.years, "percent per year", "Trends_funding", "")
            add("Age trends", f"{a} {kind} APC p", tr.p, tr.years, "slope p-value", "Trends_funding", "")

    # Adult max share (the v1 summary said adult-only funding never exceeded a small cap)
    adult = age[age.age == "Adult"]
    add("Age", "Adult share of CHD $ maximum (any FY)", float(adult.pct_of_CHD.max()),
        f"FY{int(adult.loc[adult.pct_of_CHD.idxmax()].FY)}", "percent of CHD $", "Age_pct_v2.4", "")
    add("Age", "Adult dollars maximum (any FY)", float(adult.USD_M.max()),
        f"FY{int(adult.loc[adult.USD_M.idxmax()].FY)}", "$ millions, nominal", "Age_USD_M_v2.4", "")
    # FY2020-2024 pediatric share range
    ped = age[(age.age == "Pediatric") & age.FY.between(2020, 2024)]
    add("Age", "Pediatric share of CHD $ min FY2020-2024", float(ped.pct_of_CHD.min()),
        f"FY{int(ped.loc[ped.pct_of_CHD.idxmin()].FY)}", "percent of CHD $", "Age_pct_v2.4", "")
    add("Age", "Pediatric share of CHD $ max FY2020-2024", float(ped.pct_of_CHD.max()),
        f"FY{int(ped.loc[ped.pct_of_CHD.idxmax()].FY)}", "percent of CHD $", "Age_pct_v2.4", "")

    # NHLBI
    ic = ic_shares(proj)
    for window, d in ic.items():
        add("IC", f"NHLBI (HL) share of CHD $ {window}", d["nhlbi_pct"], window, "percent of CHD $",
            "Projects in outputs/v2.4/chd_v2_funding.xlsx", f"NHLBI dollars {d['nhlbi']:.4f} of {d['total']:.4f} million")

    # RCDC overlap
    ro = rcdc_outside(O)
    add("RCDC", "Share of RCDC dollars outside v2.4 combined, FY2016-2025", ro["pct_rcdc_dollars_outside_v24"],
        "FY2016-2025", "percent of RCDC $", "Overlap_v2.4_vs_RCDC",
        f"RCDC-only {ro['rcdc_only_M']:.4f} of {ro['rcdc_total_M']:.4f} million")
    add("RCDC", "Share of v2.4 combined dollars also in RCDC, FY2016-2025", ro["pct_v24_dollars_inside_rcdc"],
        "FY2016-2025", "percent of v2.4 $", "Overlap_v2.4_vs_RCDC", "")
    rcdc = D[D.FY.between(2016, 2025)]
    add("RCDC", "RCDC CHD dollars minimum FY2016-2025", float(rcdc.rcdc_USD_M.min()),
        f"FY{int(rcdc.loc[rcdc.rcdc_USD_M.idxmin()].FY)}", "$ millions, nominal", "Yearly_v2.4", "RCDC is independent of the v2.4 rule")
    add("RCDC", "RCDC CHD dollars maximum FY2016-2025", float(rcdc.rcdc_USD_M.max()),
        f"FY{int(rcdc.loc[rcdc.rcdc_USD_M.idxmax()].FY)}", "$ millions, nominal", "Yearly_v2.4", "RCDC is independent of the v2.4 rule")
    add("RCDC", "RCDC % of NIH minimum FY2016-2025", float(rcdc.rcdc_pct_of_NIH.min()),
        f"FY{int(rcdc.loc[rcdc.rcdc_pct_of_NIH.idxmin()].FY)}", "percent", "Yearly_v2.4", "")
    add("RCDC", "RCDC % of NIH maximum FY2016-2025", float(rcdc.rcdc_pct_of_NIH.max()),
        f"FY{int(rcdc.loc[rcdc.rcdc_pct_of_NIH.idxmax()].FY)}", "percent", "Yearly_v2.4", "")
    for _, r in O.dropna(subset=["FY"]).iterrows():
        fy = int(r.FY)
        add("RCDC", f"FY{fy} both dollars", r.both_M, f"FY{fy}", "$ millions", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} v2.4-only dollars", r.classifier_only_M, f"FY{fy}", "$ millions", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} RCDC-only dollars", r.rcdc_only_M, f"FY{fy}", "$ millions", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} both n", r.both_n, f"FY{fy}", "project-years", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} v2.4-only n", r.classifier_only_n, f"FY{fy}", "project-years", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} RCDC-only n", r.rcdc_only_n, f"FY{fy}", "project-years", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} % of v2.4 projects also in RCDC", r.pct_classifier_in_rcdc, f"FY{fy}", "percent", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} % of RCDC projects also in v2.4", r.pct_rcdc_in_classifier, f"FY{fy}", "percent", "Overlap_v2.4_vs_RCDC", "")
        add("RCDC", f"FY{fy} intersection-over-union (dollars)", r.iou_dollars, f"FY{fy}", "index 0-1", "Overlap_v2.4_vs_RCDC", "")

    # Periods
    for _, r in periods.iterrows():
        add("Shares", f"Pooled CHD % of NIH CVD {r.period}", r.CHD_pct_of_CVD, r.period, "percent", "CVD_periods_v2.4", "pooled dollars, not mean of yearly shares")
        add("Shares", f"Pooled CHD % of NIH {r.period}", r.CHD_pct_of_NIH, r.period, "percent", "CVD_periods_v2.4", "pooled dollars, not mean of yearly shares")

    # Mortality (counts unchanged from v1)
    w13, w24 = W[W.year == 2013].iloc[0], W[W.year == 2024].iloc[0]
    def mort_range(col, label, unit="percent"):
        add("Mortality", f"{label} 2013", w13[col], "2013", unit, "Mortality_yearly", "Death counts unchanged from v1")
        add("Mortality", f"{label} 2024", w24[col], "2024", unit, "Mortality_yearly", "Death counts unchanged from v1")
        add("Mortality", f"{label} min 2013-2024", float(W[col].min()), f"{int(W.loc[W[col].idxmin()].year)}", unit, "Mortality_yearly", "")
        add("Mortality", f"{label} max 2013-2024", float(W[col].max()), f"{int(W.loc[W[col].idxmax()].year)}", unit, "Mortality_yearly", "")

    mort_range("chd_ucd_pct_of_cvd_all", "CHD underlying-cause share of CVD deaths, all ages")
    mort_range("chd_any_pct_of_cvd_all", "CHD any-mention share of CVD deaths, all ages")
    mort_range("chd_ucd_pct_of_cvd_ped", "CHD underlying-cause share of CVD deaths, children (0-17)")
    mort_range("chd_any_pct_of_cvd_adult", "CHD any-mention share of CVD deaths, adults")
    mort_range("chd_ucd_pct_of_cvd_adult", "CHD underlying-cause share of CVD deaths, adults")
    add("Mortality", "Pediatric underlying-cause CHD deaths 2013", int(w13.chd_ucd_ped), "2013", "deaths", "Mortality_yearly", "Unchanged from v1")
    add("Mortality", "Pediatric underlying-cause CHD deaths 2024", int(w24.chd_ucd_ped), "2024", "deaths", "Mortality_yearly", "Unchanged from v1")
    add("Mortality", "Adult any-mention CHD deaths 2013", int(w13.chd_any_adult), "2013", "deaths", "Mortality_yearly", "Unchanged from v1")
    add("Mortality", "Adult any-mention CHD deaths 2024", int(w24.chd_any_adult), "2024", "deaths", "Mortality_yearly", "Unchanged from v1")
    add("Mortality", "Adult any-mention CHD deaths percent change 2013-2024",
        100 * (w24.chd_any_adult / w13.chd_any_adult - 1), "2013-2024", "percent", "Mortality_yearly", "100*(2024/2013 - 1)")

    # mortality-window APCs (deaths + v2.4 funding share)
    name_map = {
        "chd_ucd_ped": "Pediatric underlying-cause CHD deaths",
        "chd_any_adult": "Adult any-mention CHD deaths",
        "chd_ucd_pct_of_cvd_ped": "Pediatric UCD CHD share of CVD deaths",
        "chd_any_pct_of_cvd_adult": "Adult any-mention CHD share of CVD deaths",
        "chd_ucd_pct_of_cvd_all": "All-ages UCD CHD share of CVD deaths",
        "chd_any_pct_of_cvd_all": "All-ages any-mention CHD share of CVD deaths",
        "CHD_pct_of_CVD_funding": "CHD % of NIH CVD funding (aligned to mortality years)",
    }
    for series, label in name_map.items():
        s = mort_tr[mort_tr.series == series]
        if s.empty:
            continue
        tr = s.iloc[0]
        add("Mortality trends", f"{label} APC", tr.APC_pct, "2013-2024", "percent per year", "Mortality_trends",
            "v2.4 funding share on the funding series; death series unchanged from v1")
        add("Mortality trends", f"{label} APC 95% CI low", tr.APC_lo, "2013-2024", "percent per year", "Mortality_trends", "")
        add("Mortality trends", f"{label} APC 95% CI high", tr.APC_hi, "2013-2024", "percent per year", "Mortality_trends", "")
        add("Mortality trends", f"{label} APC p", tr.p, "2013-2024", "slope p-value", "Mortality_trends", "")

    rows.extend(_val_rows_from_scoring())
    return pd.DataFrame(rows)


def write_key_markdown(df, path: Path):
    lines = [
        "# Key numbers for the v2.4 CHD funding, share, and mortality tables",
        "",
        "All numbers were read from the listed source files or from `chd_v2.4_shares_mortality.xlsx` produced in this folder. None were estimated or rounded before being recorded here; a suggested rounding is shown only as a convenience.",
        "Dollars are nominal. FY2026 is a partial year (records through 20 October 2026) and is excluded from APC/CAGR (FY2013–2025). Mortality counts are unchanged from v1.",
        "",
    ]
    for section, g in df.groupby("section", sort=False):
        lines.append(f"## {section}")
        lines.append("")
        lines.append("| Item | Value | Window | Unit | Source sheet or file | Note |")
        lines.append("|---|---|---|---|---|---|")
        for _, r in g.iterrows():
            v = r["value"]
            if isinstance(v, float):
                disp = f"{v:.6g}"
            else:
                disp = "" if pd.isna(v) else str(v)
            src = Path(str(r["source_file"])).name
            sheet = r["source_sheet"]
            srcdisp = f"{src} / {sheet}" if sheet and not str(sheet).startswith("Projects") else f"{src} — {sheet}" if sheet else src
            if str(r["source_sheet"]).startswith("Projects") or str(r["source_file"]).endswith(".xlsx") and "review_scoring" in str(r["source_file"]):
                srcdisp = f"{Path(str(r['source_file'])).name} / {r['source_sheet']}"
            note = (r["note"] or "").replace("|", "/")
            lines.append(f"| {r['item']} | {disp} | {r['window']} | {r['unit']} | {srcdisp} | {note} |")
        lines.append("")
    path.write_text("\n".join(lines))
    return path





def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    forbidden = {
        (ROOT / "outputs").resolve(),
    }
    if out.resolve() == (ROOT / "outputs").resolve() or out.resolve() == (ROOT / "outputs" / "v2.4").resolve():
        sys.exit(f"Refusing to write to {out}; outputs must go under outputs/v2.4/figures_tables/")

    print("Loading shipped denominators, v2.4 Projects, WONDER ...")
    denoms = load_denominators()
    proj = load_v24_projects()
    W0, ov, Rraw = mortality_from_wonder()

    print("Computing v1 keyword shares (self-check) ...")
    D_v1 = yearly_v1(denoms)
    age_v1 = age_from_v1()
    trends_v1 = funding_trends(D_v1, age_v1,
                               ["Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear"],
                               "v1 keyword")
    W_v1 = W0.copy()
    W_v1 = W_v1.merge(D_v1[["FY", "CHD_pct_of_CVD"]].rename(columns={"FY": "year", "CHD_pct_of_CVD": "CHD_pct_of_CVD_funding"}),
                      on="year", how="left")
    mort_tr_v1 = mortality_trends(W_v1)

    ok, check_text = self_check(D_v1, age_v1, W_v1, trends_v1, out / "self_check_v1.txt")
    print(check_text)
    if not ok:
        sys.exit("v1 self-check failed; not writing v2.4 workbook or figures.")

    print("Computing v2.4 combined shares ...")
    D_v24 = yearly_v24(denoms, proj)
    yl = pd.read_excel(V24_FUNDING, "Yearly")
    for _, r in yl.iterrows():
        got = float(D_v24.loc[D_v24.FY == int(r.FY), "CHD_USD_M"].iloc[0])
        if round(got, 2) != round(float(r.combined_M), 2):
            sys.exit(f"v2.4 combined $ mismatch FY{int(r.FY)}: {got} vs workbook {r.combined_M}")
    age_v24_df = age_from_v24(proj, in_cvd=False)
    age_incvd_v24 = age_from_v24(proj, in_cvd=True)
    trends_v24 = funding_trends(D_v24, age_v24_df,
                                ["Pediatric", "Adult", "Both", "Not age-specific"],
                                "v2.4 combined")
    W_v24 = W0.copy()
    W_v24 = W_v24.merge(D_v24[["FY", "CHD_pct_of_CVD"]].rename(columns={"FY": "year", "CHD_pct_of_CVD": "CHD_pct_of_CVD_funding"}),
                        on="year", how="left")
    mort_tr_v24 = mortality_trends(W_v24)
    O_v24 = overlap_vs_rcdc(proj)
    periods_v24 = pd.DataFrame([
        period_pooled(D_v24, range(2013, 2016), "FY2013-2015"),
        period_pooled(D_v24, range(2023, 2026), "FY2023-2025"),
    ])
    trends_all = pd.concat([trends_v1, trends_v24], ignore_index=True)
    compare = comparison_sheet(D_v1, D_v24, trends_v1, trends_v24, age_v1, age_v24_df, mort_tr_v1, mort_tr_v24)
    keynums = build_key_numbers(D_v24, age_v24_df, trends_v24, W_v24, mort_tr_v24, O_v24, periods_v24, proj,
                                "chd_v2.4_shares_mortality.xlsx")
    write_key_markdown(keynums, out / "key_numbers_v2.4.md")
    print(f"Wrote {out / 'key_numbers_v2.4.md'} ({len(keynums)} rows)")

    check_df = pd.DataFrame({"line": check_text.splitlines()})
    payload = dict(
        D_v1=D_v1, D_v24=D_v24,
        age_v1=age_v1, age_v24=age_v24_df,
        age_incvd_v1=None, age_incvd_v24=age_incvd_v24,
        trends_v1=trends_v1, trends_v24=trends_v24, trends_all=trends_all,
        W_v1=W_v1, W_v24=W_v24, ov=ov, mort_tr_v1=mort_tr_v1, mort_tr_v24=mort_tr_v24,
        O_v24=O_v24, periods_v24=periods_v24, compare=compare, key_numbers=keynums,
        check_df=check_df, check_header="v1 self-check log from this run. ALL CHECKS PASSED required before this workbook was written.",
    )
    xlsx = out / "chd_v2.4_shares_mortality.xlsx"
    write_workbook(xlsx, payload)
    print(f"Wrote {xlsx}")
    cache = out / "_tables.pkl"
    payload_to_save = {k: v for k, v in payload.items() if k not in ("check_df", "check_header")}
    pd.to_pickle(payload_to_save, cache)
    print(f"Wrote {cache} (local cache; not required to re-run figures if the workbook is present)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
