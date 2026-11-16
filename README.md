# NIH funding for congenital heart disease (CHD) research, FY2013–2026

This repository holds a transparent, two-tier keyword classifier and the
validation materials used to estimate NIH support for congenital heart disease
research in fiscal years 2013–2026. The current release is **v2.4**.

The input records are public NIH ExPORTER / RePORTER project and abstract
files. The universe is every project administered by an NIH Institute or
Center, collapsed to one record per full project number per fiscal year and
valued at the parent award's total cost (direct plus indirect; component costs
are used only when no parent record exists, so multicomponent awards are never
double-counted). Dollars are nominal. FY2026 is a partial fiscal year
(retrieved 20 October 2026) and is shown but excluded from trend windows.

Outputs and review workbooks in this repository are de-identified:
investigator names do not appear in code, documentation, or shipped tables.
NIH abstract and public-health-relevance text is kept verbatim. Reviewer
initials have been replaced with generic codes (R1, R2, R3).

## Reproduce the v2.4 results

From the repository root, with R 4.3+ (tested on 4.5.3) and the packages in
`REQUIREMENTS-R.txt` (readxl, openxlsx). Arial is used for the figures when it
is installed:

```bash
Rscript R/run_v2.4_all.R
```

This classifies the CHD-signal pool at v2.4, writes the funding workbook and
the in-sample / V3 / V4 / combined-estimate scores, rebuilds the share and
mortality tables (including the v1 self-check), and renders the figures.
Outputs go to `outputs/v2.4/r/` by default so the shipped tables in
`outputs/v2.4/` are not overwritten. To write elsewhere:

```bash
CHD_V2_OUT=/tmp/chd_v24_repro \
CHD_FIG_OUT=/tmp/chd_v24_repro/figures_tables \
CHD_REF_OVERRIDES=data/validation/v2.3_reference_overrides.xlsx \
Rscript R/run_v2.4_all.R
```

The R classifier reads `data/work/v2_pool.tsv.xz`, a tab-separated, xz-compressed
export of the shipped pickle `data/work/v2_pool.pkl.gz`, verified row-for-row
(title and text checksums match). Bootstrap confidence intervals use the
resampling index matrices in `data/bootstrap/` (drawn with NumPy
`default_rng(1)` in the Python pipeline) so the R intervals match the shipped
tables. A comparison of an R run against the shipped Python outputs is in
`tests/r_vs_python_report.md`.

Earlier R scripts (`R/00_setup.R`–`R/12_*.R`, `config.R`) document the v1
classifier, CVD denominator, and CDC WONDER comparison. They are not required
to reproduce the v2.4 totals. Raw ExPORTER bulk files are not shipped; see
`data/FETCH.md` if you want to rebuild the pool from public NIH exports. Do
not run `assemble.py`.

### Python alternative

The same v2.4 steps can be run with Python 3.11+ and the packages in
`REQUIREMENTS.txt` (pandas ≥ 2.2, numpy, openpyxl, pyreadr, statsmodels,
matplotlib, and Pillow):

```bash
python3 R/14_v2_run.py
python3 R/21_v24_shares.py
python3 R/22_v24_figures.py
```

or `bash R/run_v24_shares.sh` for the last two steps. `R/14_v2_run.py` reads
`data/work/v2_pool.pkl` or, if that file is absent, the shipped
`data/work/v2_pool.pkl.gz`. It writes `outputs/v2.4/chd_v2_funding.xlsx` and
the in-sample / review-set scoring workbooks (the review files those steps
need are already in `data/validation/` and `outputs/`). To write a fresh copy
without overwriting the shipped tables:

```bash
CHD_V2_OUT=/tmp/chd_v24_repro \
CHD_V2_CLASSIFIED=/tmp/v2.4_classified.pkl \
python3 R/14_v2_run.py
```

The `Yearly` sheet of the new workbook should match
`outputs/v2.4/chd_v2_funding.xlsx` (and `outputs/v2.4/yearly_expected.csv`).
A pandas 3.x environment is preferred; the shipped pickle uses protocol 4 with
plain Python dtypes.

`R/21_v24_shares.py` first rebuilds the v1 keyword shares from the shipped
yearly denominators and checks them against `data/work/v1_expected_*.csv`
(including CHD as a share of NIH CVD funding 2.2124% in FY2013 and 2.1654% in
FY2025, and as a share of all NIH funding 0.2257% to 0.2033%). The v2.4
workbook is written only if that check passes. Python figure and share outputs
go to `outputs/v2.4/figures_tables/`: yearly dollars and shares, the age split
(dollars and share of CHD dollars, with APC and CAGR), overlap with the RCDC
CHD category, a funding-vs-mortality comparison using the shipped aggregated
CDC WONDER death counts, a key-numbers table, and figures (`Fig1`–`Fig8` and
`Fig_main_two_panel`, PNG + PDF, and TIF for the main two-panel figure).
Classification rules are not changed. The full grant universe is not required;
denominators and flags are in `data/work/` and `data/wonder/wonder_long.csv`
(see `data/README.md`).


## Inclusion and exclusion rules (v2.4)

The primary definition is a two-tier keyword classifier applied to the title
and to the pooled abstract and public-health-relevance text.

**Tier 1, "CHD-focused."** A project qualifies if it has 1 or more strong CHD
terms in the title; or 3 or more strong-term mentions; or 2 strong mentions
plus 2 or more weak mentions; or 1 strong mention together with a
pediatric-cardiac title. Strong terms name CHD or a specific lesion or
palliation (for example Fontan, single ventricle, hypoplastic left heart
syndrome, tetralogy of Fallot, transposition, coarctation, septal defects,
Ebstein anomaly, truncus arteriosus, double-outlet right ventricle, atresias,
TAPVR, heterotaxy, conotruncal defects, Norwood, cavopulmonary, ACHD, patent
ductus arteriosus / arterial ductus, and supravalvular aortic stenosis).
Ambiguous abbreviations are excluded (CHD as coronary heart disease, ASD as
autism, VSD as voltage-sensing domain, HLHS as a library acronym, PDA as
pancreatic ductal adenocarcinoma). Post-infarction (acquired) VSD is excluded.
Broad platforms and centers are dropped when CHD is not in the title, unless
the title names CHD, heart development, or a pediatric population.

A conservative study-aim gate then demotes keyword-positive grants whose title
does not already name CHD, a kept lesion, a pediatric-cardiac setting, or
cardiac situs, and whose CHD or strong terms appear only as an associated
phenotype of a gene or protein under study. Associated-phenotype tails are
stripped; the grant stays if CHD remains in aims language or in at least two
other sentences, or if a kept lesion or substantial cardiogenesis vocabulary
plus a CHD or lesion mention is present. A grant demoted from Tier 1 can still
be Tier 2.

**Tier 2, "CHD-related basic/developmental science"** (not already Tier 1), any
of: (a) developmental-science vocabulary scoring at least 3, a
cardiac/developmental title, and an anchor (RCDC CHD or any CHD mention);
(b) a pediatric CHD device route; (c) a trainee F30/F31 with a cardiac
developmental or lesion term plus an anchor. Left-right asymmetry, patterning,
axis, and laterality terms count toward the developmental-science score and
title gate only when the same grant also has a cardiac or CHD link (heart,
cardiac, a kept lesion, or cardiac/heart/c-looping). Bare heterotaxy or
organ-specific non-cardiac laterality does not count. Platform/center titles,
acquired-disease titles, and arrhythmia/channel/sudden-death titles are
excluded from Tier 2.

**Standing exclusions (v2.3, unchanged in v2.4).** Titles that name pediatric
or neonatal pulmonary hypertension (including PPHN), congenital heart block
(including neonatal lupus), or noncompaction cardiomyopathy are not CHD unless
the title also names another CHD lesion or palliation. Coarctation, patent
ductus arteriosus, and supravalvular aortic stenosis remain included.

The comparator is the NIH RCDC category "Congenital Heart Disease" (RePORTER
category 3533), which exists only for FY2016–2025. Full rule code is
`R/13_v2_rules.py` (`VERSION = "2.4"`). Earlier frozen rule modules
(`R/13_v2_rules_v2.0.py` through `_v2.3.py`) are kept so prior versions can be
re-run.

Age focus (v2 onward) is Pediatric / Adult / Both / Not age-specific.

## Headline v2.4 results

Combined CHD funding (Tier 1 + Tier 2), nominal $ millions, from
`outputs/v2.4/chd_v2_funding.xlsx`:

| FY   | Tier 1 | Tier 2 | Combined | RCDC | Combined as % of RCDC |
|------|--------|--------|----------|------|------------------------|
| 2013 | 60.91  | 13.30  | 74.21    | —    | —                      |
| 2014 | 62.36  | 14.68  | 77.04    | —    | —                      |
| 2015 | 62.29  | 11.97  | 74.26    | —    | —                      |
| 2016 | 75.66  | 14.39  | 90.05    | 117.12 | 76.9%                |
| 2017 | 90.71  | 16.10  | 106.81   | 127.17 | 84.0%                |
| 2018 | 81.17  | 16.66  | 97.83    | 124.86 | 78.4%                |
| 2019 | 85.97  | 14.52  | 100.50   | 137.03 | 73.3%                |
| 2020 | 85.74  | 15.05  | 100.79   | 138.72 | 72.7%                |
| 2021 | 95.68  | 17.73  | 113.41   | 137.59 | 82.4%                |
| 2022 | 99.27  | 17.05  | 116.33   | 137.52 | 84.6%                |
| 2023 | 101.17 | 18.47  | 119.65   | 158.66 | 75.4%                |
| 2024 | 99.21  | 17.90  | 117.11   | 158.68 | 73.8%                |
| 2025 | 88.52  | 16.43  | 104.95   | 142.32 | 73.7%                |
| 2026 | 91.31  | 19.98  | 111.29   | —    | — (partial year)       |

The FY2013–2025 combined range is 74.21–119.65 (peak in FY2023). Relative to
v2.3, FY2013 and FY2022 combined totals are unchanged; FY2025 Tier 1 is 88.52
(was 89.19) and combined is 104.95 (was 105.62). v2.4 drops two cores (5
project-years, $2.42M): a polycystic-kidney-protein structural study (Tier 1 →
not CHD, FY2024–2026) and a stomach-curvature laterality R21 (Tier 2 → not CHD,
FY2023–2024). Both had already been labelled No by reviewers (corrected false
positives, not new false negatives). V4-115 and V4-116 remain pipeline-positive.

**V3 review (unchanged vs v2.3), reviewer Yes or Partly = CHD, Unsure excluded.**
Unweighted sensitivity 87.9% (81.0–92.5), specificity 91.8% (83.2–96.2),
PPV 94.8%, κ 0.777 (109 / 6 / 15 / 67). Headline weighted figure, excluding the
no-signal (V7) stratum: sensitivity 83.6% (77.8–89.9), specificity 97.6%
(94.9–99.5), PPV 96.8%, κ 0.820.

**V4 clear-case review, n = 198 after excluding two Unsure rows.** Unweighted
sensitivity 100% (96.3–100), specificity 98.0% (92.9–99.4), PPV 98.0%,
κ 0.980 (99 / 2 / 0 / 97). Weighted, all strata: PPV 97.2%, κ 0.986. Remaining
disagreements: V4-115 and V4-116 only.

**Combined estimate** across the reviewed sets: sensitivity 77.6% (72.0–83.7),
specificity 98.2% (96.9–99.3), PPV 98.1%, κ 0.744.

Reviewer Yes or Partly counts as CHD; Unsure rows are excluded. Weighted
figures use inverse-probability weights and a stratified bootstrap (2,000
draws, seed 1) with Wilson intervals for unweighted binomial metrics. See
`METHODS.md` and the workbooks in `outputs/v2.4/`.

## Version history

- **v1.** Title/abstract keyword rule, RCDC comparison, age-focus groups, a
  seeded manual review (833 grants), a CVD denominator, and a CDC WONDER
  mortality comparison.
- **v2 (2026-11-03).** Two-tier definition after a priority recheck: Tier 1
  tightens the v1 keyword rule; Tier 2 adds CHD-related developmental science,
  a pediatric-device route, and an F30/F31 trainee route. Age focus is
  simplified to Pediatric / Adult / Both / Not age-specific.
- **v2.1 (2026-11-04).** Patent ductus arteriosus and supravalvular aortic
  stenosis become strong lesions; the F30/F31 route requires a lesion or
  cardiac developmental term. A new V3 200-grant review covers all tiers and
  the rest of the NIH portfolio.
- **v2.2 (2026-11-04).** Coarctation (any mention), congenital heart block
  (fetal/neonatal/autoimmune forms), and pediatric pulmonary hypertension are
  added; reference labels are updated in
  `data/validation/v2.2_reference_overrides.xlsx`.
- **v2.3 (2026-11-04).** Pediatric pulmonary hypertension, congenital heart
  block, and noncompaction cardiomyopathy are excluded unless another CHD
  lesion is also named in the title. Coarctation, PDA, and SVAS stay.
  Reference labels: `data/validation/v2.3_reference_overrides.xlsx`.
- **V4 review (2026-11-04 / 2026-11-10).** A 200-grant clear-case set drawn
  under v2.3 rules and later scored against v2.3, then v2.4.
- **v2.4 (2026-11-10).** Laterality terms require a document-level cardiac or
  CHD link; Tier 1 adds the study-aim gate described above. Reference labels
  are not changed. This is the current release.

Details are in `CHANGELOG.md` and `METHODS.md`. Frozen rule modules for
v2.0–v2.3 remain in `R/`.

## License

Code is released under the MIT License (see `LICENSE`). NIH ExPORTER and
RePORTER records are U.S. government public data and are not covered by that
license.
