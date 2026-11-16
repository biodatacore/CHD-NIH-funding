# Shipped NIH extract and WONDER XML

This folder is the de-identified cache used by `R/run_all_v2.4.R`.

Retrieval date: 20 October 2026 (FY2013–2025 ExPORTER project and abstract
files; FY2026 from the RePORTER API; partial year, excluded from trends).
The universe is every project administered by an NIH Institute or Center,
collapsed to one record per full project number per fiscal year and valued
at the parent award's total cost.

- `universe/chd_universe_{FY}.csv.gz` — identifiers, IC, activity, dollars,
  RCDC CHD flags, v1 keyword-count features, and the v1 CVD flag (`cv` =
  the WHR `broad2` definition already applied to this universe). No titles,
  abstracts, investigator names, or contact fields.
- `text/chd_text_{FY}.csv.gz` — title and pooled abstract/public-health text
  for CHD-signal candidates only (the 13a pool). Abstract text is verbatim
  NIH text. `source` is `api_intramural` when the FY2020/2024 intramural
  replacement was used, otherwise `file`.
- `wonder/*.xml` — CDC WONDER XML responses used to rebuild
  `data/wonder/wonder_long.csv`.
- `MD5SUMS` — MD5 checksums, verified by `R/02_load_shipped.R`.

Every file is under 20 MB. See `data/README.md` for more detail.
