# R vs Python comparison (v2.4)

This report compares a clean `Rscript R/run_v2.4_all.R` run (outputs under
`outputs/v2.4/r/`, so the shipped Python tables were not overwritten) against
the shipped Python outputs in `outputs/v2.4/`. The R run used R 4.5.3
(2026-03-11) with `readxl` 1.6.0 and `openxlsx` 4.2.9. Arial was available to
cairo and is embedded in the figure PDFs.

Classifier rules were not changed. The R classifier reads
`data/work/v2_pool.tsv.xz` (a tab-separated, xz-compressed export of
`data/work/v2_pool.pkl.gz`). Title and abstract/public-health text checksums
match the pickle row-for-row (10,071 project-years). The TSV is loaded with
`utils::read.delim(..., strip.white = FALSE)` so leading/trailing spaces and
CSV-style quotes are preserved. The pickle remains in the repository for the
Python path.

Bootstrap confidence intervals use the resampling index matrices in
`data/bootstrap/*.idx.xz`. Those are the draws from NumPy `default_rng(1)` /
`Generator.choice` (with replacement, stratified) used by the Python scorer,
stored as 2000-by-n little-endian int32 matrices with an 8-byte nrow/ncol
header, xz-compressed. pandas `DataFrame.quantile` (type 7) is matched by R
`quantile(..., type = 7)`. If an index file is absent, the R scorer falls back
to `set.seed(1)` + `sample()`, which would **not** match NumPy's draws; with
the shipped indices, the intervals match.

## What matched exactly

| Check | Result |
| --- | --- |
| Classification, all 10,071 project-years | 0 differences on `tier`, `t2_route`, `t1_drop`, `age_v2`, `chd_v2`, `tier1`, `tier2`, `kw`, and aim-gate counts `t1_n_aim`, `t1_n_subst`, `t1_n_assoc`. Combined 2,826 (2,255 Tier 1, 571 Tier 2). |
| Funding workbook sheets | Same nine sheets. Yearly, Age_summary, Age_USD_M_combined / pct / tier1 / v1, Tier2_routes, and Tier1_drops: 0 differences at 1e-9 (rounded sheets identical). |
| Funding Projects | 2,860 / 2,860 rows, same order; USD, tier, kw, rcdc, age_v2, and titles match. |
| In-sample Metrics | 84 / 84 rows; estimates and CIs agree to ~1e-15 when aligned on Label / Reviewer CHD = / Definition / Weighting / Metric. |
| V2 set Summary | 28 / 28; estimates and CIs to ~1e-15. |
| Combined estimate | 14 / 14, nX = 876; estimates and CIs to ~1e-15. |
| V3 Summary | 28 / 28; estimates and CIs to ~1e-15. |
| V3 Weighted_with_without_V7 | 20 / 20; estimates and CIs to ~1e-15. |
| V4 Summary | 44 / 44, nX = 198; estimates and CIs to ~1e-15. |
| V4 Age | `n both-sides CHD` 99, capitalization-normalized 1, Both-(unclear) excluded 1, n used 95, agreement 0.6, kappa 0.38720081480224 (diff 4e-16). |
| Shares workbook | All 16 sheet names match the Python workbook. |
| Yearly_v2.4, Yearly_v1_keyword, Age_USD_M_v2.4, Age_pct_v2.4, Age_in_CVD_USD_M_v2.4, Overlap, CVD_periods, Mortality_yearly, Mortality_splice_check, README | Row-aligned values identical at 1e-9 (most exactly 0). |
| Trends_funding (36 rows, including v1 and v2.4 APC/CAGR) | Identical after writing the same 4-decimal rounding as Python. Unrounded APC/CAGR used in key numbers agree to ~1e-12, well inside 1e-6. |
| Mortality_trends (25 rows) | Identical at 4 decimals, same series order and `y2013` / `y2024` columns. |
| v1_vs_v2.4 (203 rows) | Identical at 1e-9. |
| Key numbers | **546 / 546** items and values; numeric max absolute difference 2.6e-12. Windows, units, and sections match. |
| v1 self-check | **ALL CHECKS PASSED** (393-line Self_check sheet and `self_check_v1.txt`). |
| Figures | All `Fig1`–`Fig8`, `Fig4-5_..._two_panel` (PNG+PDF) and `Fig_main_two_panel` (PNG+PDF+TIF) are written. Base-R devices, Arial, no grid, age-group colors (Pediatric `#1f5fa8`, Adult `#c0392b`, Both `#7b4fa0`, Not age-specific grey45), FY2026 lighter and labelled `2026*`. Plotted values match the share tables. Visual layout follows the Python figures (dual axes, stacked age bars, captions). Pixel identity is not required and was not claimed. |

Headline unrounded totals (both pipelines): FY2013 combined $74.209262M (146 project-years); peak $119.646064M in FY2023 (244); FY2025 $104.951853M (215). CHD dollars APC 3.920915% (CAGR 2.930559%, p = 0.000107722); CHD % of NIH CVD APC −0.427446%; CHD % of all NIH APC −0.969125%.

## What could not be matched exactly, and why

- **One 4-decimal cell in `Age_USD_M_v1`.** FY2021 Unclear dollars are 7.8819 in the shipped Python sheet and 7.8820 in the R sheet (difference 0.0001 after the shared 4-decimal rounding). This does not affect APC/CAGR (1e-6), key numbers, or any v2.4 combined total.
- **Key-number `note` wording.** 29 notes differ only in how interval endpoints are formatted (full-precision vs shorter text). Item names and `value` columns still match 546 / 546.
- **Some V4 / label-change review-set sheets are not fully ported.** The required scoring point estimates, CIs, and V4 Age row are produced and match. The R V4 workbook does not yet write every Python 20 accessory sheet (Unsure, Prior_label_*, Proposed_rule_changes, Integrity). The label-change workbook records the same five portfolio project-year changes (2 cores) but may list them in a different row order, and the review-set change tables are not fully ported. Key numbers read Summary / Weighted_with_without_V7 / Combined_estimate / Age, which are present.
- **Figures are visually equivalent, not pixel-identical.** Rendering is base R / cairo rather than matplotlib. Titles, colors, series, FY2026 treatment, and numeric annotations match; spacing, caption wrapping, and exact pixel size differ (Python used `bbox_inches="tight"`).
- **Bootstrap CIs without the shipped indices.** The fallback R generator is documented above. This run used the shipped indices, so CIs matched.
- **13a pool rebuild is not ported.** The public repository does not ship the full grant universe. Reproduction starts from the shipped pool (`v2_pool.pkl.gz` or `v2_pool.tsv.xz`).

## How to repeat the comparison

```bash
Rscript R/run_v2.4_all.R
python3 tests/compare_r_vs_python.py
```

The entry point writes to `outputs/v2.4/r/` by default. Set `CHD_V2_OUT` and
`CHD_FIG_OUT` to choose another directory. Default reference-label overrides
are `data/validation/v2.3_reference_overrides.xlsx`.
