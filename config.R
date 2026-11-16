#' config.R -- paths and constants for the NIH congenital heart disease (CHD) funding project.
#'
#' The self-contained path (Rscript R/run_all_v2.4.R) loads the de-identified
#' extract in data/shipped/ and does not need these caches. Optional rebuilds
#' from raw ExPORTER / RePORTER files can reuse a WHR-style project cache:
#' one project table per fiscal year (proj_{FY}.rds), the FY2020/2024
#' intramural replacement tables (projz_{FY}.rds), and the row tables
#' (rows_{FY}.rds). Those repositories are read only; nothing in them is run
#' or modified (in particular, assemble.py is never run). Set the environment
#' variables below to point at your own copies if you use that path.
CONFIG <- list(
  whr_work = Sys.getenv("CHD_WHR_WORK", "data/raw/whr_work"),  # WHR R work dir (proj/, rows/)
  raw_dir  = Sys.getenv("CHD_RAW_DIR",  "data/raw"),          # WHR raw inputs ({FY}/...)
  work_dir = "data/work",
  out_dir  = "outputs",
  years    = 2013:2026,
  exporter_years = 2013:2025, api_year = 2026,  # ExPORTER project/abstract years; FY2026 from the RePORTER API
  zfix_years = c(2020, 2024),
  incomplete_year = 2026,            # FY2026 retrieved 2026-10-20 (WHR snapshot); partial year
  trend_years = 2013:2025,           # trend statistics exclude the partial FY2026
  rcdc_chd_id = 3533,                # RePORTER spending-category id of RCDC "Congenital Heart Disease"
  api_url = "https://api.reporter.nih.gov/v2/projects/search",
  seed = 20261026,
  font = "Arial"
)
# NIH Institutes/Centers (administering IC codes); identical to the WHR universe filter (S3.1).
NIH_ICS <- c("AA", "AG", "AI", "AR", "AT", "CA", "CL", "CT", "DA", "DC", "DE", "DK", "EB", "ES", "EY",
             "GM", "HD", "HG", "HL", "LM", "MD", "MH", "NR", "NS", "OD", "TR", "TW", "WH")
