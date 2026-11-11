# Data shipped with this repository

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

## Not included

- Full NIH ExPORTER / RePORTER bulk extracts and any workbook intermediates
- CDC WONDER raw caches
- Older large working pickles and logs
- Manuscript drafts or correspondence
