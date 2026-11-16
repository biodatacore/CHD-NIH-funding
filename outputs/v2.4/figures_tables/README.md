# v2.4 shares, mortality comparison, and figures

This folder holds yearly CHD shares of NIH CVD funding and of all NIH funding,
age-group dollars and shares, APCs and CAGRs (FY2013–2025), overlap with the
NIH RCDC “Congenital Heart Disease” category, a funding-vs-mortality
comparison, and the figures drawn from those tables.

Rebuild from the repository root (does not change classification rules):

```bash
python3 R/21_v24_shares.py
python3 R/22_v24_figures.py
```

or `bash R/run_v24_shares.sh`. The v1 self-check must pass before the workbook
is written. Inputs are the shipped yearly denominators and flags under
`data/work/`, the aggregated CDC WONDER series `data/wonder/wonder_long.csv`,
and `outputs/v2.4/chd_v2_funding.xlsx`. Dollars are nominal. FY2026 is a
partial year (records through 20 October 2026) and is excluded from APC/CAGR.

`_tables.pkl` is a local cache for the figure script and is not required if
the workbook is present (and is gitignored).

The two-panel main figure (`Fig_main_two_panel.png` / `.tif` / `.pdf`) is
drawn at 300 dpi, Arial, in black and white with color only for age groups.
The TIF is LZW-compressed. PNG readers may report 299.9994 dpi, which is the
standard PNG encoding of 300 dpi (11811 pixels/metre).
