# Data shipped with this repository

## NIH universe and WONDER XML (self-contained rebuild)

`data/shipped/` holds the de-identified NIH Institute/Center project-year
universe actually used for the denominators and the CHD-signal pool
(ExPORTER FY2013–2025 plus the RePORTER API extract for FY2026, retrieved
20 October 2026), together with candidate title/abstract text and the CDC
WONDER XML responses behind `data/wonder/wonder_long.csv`.

- `universe/chd_universe_{FY}.csv.gz` — one row per full project number
  per fiscal year (NIH IC filter already applied): identifiers, IC,
  activity code, parent-award dollars, RCDC CHD flags, v1 keyword-count
  features, and the v1 CVD flag (`cv`, the WHR `broad2` definition already
  applied to this universe). Titles and abstracts are not in this file.
- `text/chd_text_{FY}.csv.gz` — pooled title + abstract + public-health
  text for every CHD-signal candidate (the 13a pool, including the extra
  lesion/PH rows). FY2020/2024 intramural replacement text is already
  applied (`source` is `api_intramural` or `file`). Abstract text is
  verbatim from NIH. Diversity-supplement titles use `[NAME]` in place of
  a personal name.
- `wonder/*.xml` — raw CDC WONDER XML for the D76/D77 (2013–2017
  bridged-race) and D158/D157 (2018–2024 single-race) queries. Copied into
  `data/wonder/` by `R/02_load_shipped.R`.
- `MD5SUMS` — MD5 checksums of every file under `data/shipped/`, checked
  by the loader.

Each shipped file is under 20 MB. `Rscript R/run_all_v2.4.R` rebuilds
`data/work/nih_cvd_yearly.csv`, `rcdc_chd_projects.csv`,
`v1_keyword_yearly.csv`, `v1_keyword_age.csv`, `v24_cv_flags.csv`,
`v2_pool.tsv.xz`, and `data/wonder/wonder_long.csv` from this extract and
then runs the v2.4 pipeline. Investigator and contact fields are not
shipped.


## Pipeline input for v2.4 fiscal-year totals

`data/work/v2_pool.pkl.gz` is the classified signal pool used by `R/14_v2_run.py`
(10,071 project-years). Columns include fiscal year, project numbers, institute,
activity code, award dollars, title, RCDC and keyword flags, and a `text` field
that concatenates the title with the NIH abstract and public-health-relevance
statement. Abstract text is verbatim from NIH. Titles of diversity supplements
and similar awards have personal names replaced with `[NAME]`.

The file is a pandas pickle (protocol 4) compressed with gzip. It is well under
GitHub's 100 MB file limit, so it is not split into parts. `R/14_v2_run.py` reads
`data/work/v2_pool.pkl` if that file exists, otherwise `data/work/v2_pool.pkl.gz`.

`data/work/v2_pool.tsv.xz` is a tab-separated, xz-compressed export of the same
pool for the R pipeline (`R/23_v24_classify.R`). It was generated from the
pickle and checked row-for-row (10,071 rows; title and abstract/public-health
text checksums match). Use `utils::read.delim()` with `strip.white = FALSE` to
load it; some title fields have leading or trailing spaces that must be kept.
`data/work/v2.4_classified_labels.csv.xz` holds the v2.4 classification labels
(no text) used by the R-vs-Python comparison.

## Bootstrap resampling indices

`data/bootstrap/*.idx.xz` are 2000-by-n matrices of 0-based row indices
(little-endian int32, preceded by an 8-byte nrow/ncol header, xz-compressed).
They are the draws from NumPy `default_rng(1)` / `Generator.choice` used by
the Python scorer (in-sample, V2 set, V3, V4, and the combined estimate). The
R scorer reads these files so confidence intervals match the shipped Python
tables. Regenerating draws with R's `sample()` would produce different
intervals; the point estimates would still match.

This pool is sufficient to reproduce the v2.4 fiscal-year totals and the
in-sample / review-set scores. The full NIH universe and ExPORTER bulk files are
not included (they are large public files and are not required for the v2.4
run). See `data/FETCH.md` if you want to rebuild the pool from public NIH
exports.

## Validation

`data/validation/` holds de-identified returned reviews and reference-label
override workbooks:

- `v2_review_returned.xlsx`, `v3_review_returned.xlsx`, and the v2.2/v2.3
  reference copies of the V3 return
- `v4_review_adjudicated.csv` (UTF-8)
- `priority_recheck_returned.xlsx`
- `v2.2_reference_overrides.xlsx`, `v2.3_reference_overrides.xlsx`

Original reviewer identifiers have been replaced with generic codes (R1, R2, R3)
in a column named `Reviewer code`. Comments are unchanged when they contain no
personal names.

Blinded review workbooks and answer keys live under `outputs/` (v1 833-grant
review, priority and round-2 rechecks, the v2 200-grant set, the V3 set, and
the V4 set). Final v2.4 scoring and funding tables are in `outputs/v2.4/`.


## Share, mortality, and figure tables (v2.4)

The scripts `R/21_v24_shares.py` and `R/22_v24_figures.py` do not need the full
NIH universe. They read these compact, de-identified tables (no investigator
names):

- `data/work/nih_cvd_yearly.csv` — yearly NIH and CVD denominators and RCDC
  CHD totals, aggregated from the same cached grant universe used by
  `R/07_cvd.R`.
- `data/work/v24_cv_flags.csv` — the CVD flag for each project-year in
  `outputs/v2.4/chd_v2_funding.xlsx`.
- `data/work/rcdc_chd_projects.csv` — RCDC “Congenital Heart Disease”
  project-years (FY, full project number, dollars) for the overlap tables.
- `data/work/v1_keyword_yearly.csv` and `v1_keyword_age.csv` — v1 keyword
  numerators used in the self-check and the v1 comparison sheet.
- `data/work/v1_expected_*.csv` — v1 ground-truth shares, trends, and
  mortality counts used by the self-check.
- `data/wonder/wonder_long.csv` — aggregated CDC WONDER death counts,
  rebuilt from the XML in `data/shipped/wonder/` (2013–2017 bridged-race
  final files; 2018–2024 single-race final files). No refetch is performed.

## Not included

- Raw NIH ExPORTER / RePORTER bulk extracts (the de-identified project-year
  universe and candidate text in `data/shipped/` are sufficient)
- CDC WONDER form-default HTML caches (the XML responses are shipped)
- Older large working pickles and logs
- Manuscript drafts or correspondence
