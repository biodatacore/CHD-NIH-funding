# Rebuilding the pool from public NIH files (optional)

The de-identified NIH universe in `data/shipped/` is enough to rebuild the
CHD-signal pool, the yearly denominators, and every v2.4 result:

```bash
Rscript R/run_all_v2.4.R
```

Rebuilding that extract from public NIH files is optional and is described
below. Investigator-name columns are never required and should not be kept
in any files added to a public copy of this repository.


The following steps rebuild the extract from public NIH files if you do not want to use `data/shipped/`.

1. Download NIH ExPORTER project and abstract files for FY2013–2025 from the
   NIH ExPORTER site, and (for FY2026, a partial year) query the RePORTER API
   v2 (`https://api.reporter.nih.gov/v2/projects/search`).
2. Place each fiscal year's project CSV at `data/raw/{FY}/prj.csv` and the
   corresponding abstract file alongside it. Set `CHD_RAW_DIR` and
   `CHD_WHR_WORK` if you keep a WHR-style project/row cache elsewhere.
3. Run the earlier extract/build/classify steps (`R/01_extract.R`,
   `R/02_build.R`, `R/03_classify.R`) and then `R/13a_v2_pool.py` to
   regenerate `data/work/v2_pool.pkl`.
4. Run `python3 R/14_v2_run.py` as in the top-level README.

Investigator-name columns are never required and should not be kept in any
files you add to a public copy of this repository.

The compact yearly NIH/CVD denominators used by the share tables live in
`data/work/nih_cvd_yearly.csv` and are rebuilt from `data/shipped/` by
`R/run_all_v2.4.R`. The optional raw rebuild above produces the same
universe when the same cached extract (retrieved 20 October 2026) is used.

