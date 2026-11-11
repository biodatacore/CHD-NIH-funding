# Rebuilding the pool from public NIH files (optional)

The shipped `data/work/v2_pool.pkl.gz` is enough to reproduce the v2.4
fiscal-year totals. Rebuilding the pool from scratch is optional and requires
public NIH data that are too large to keep in this repository.

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
