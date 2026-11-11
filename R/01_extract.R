#' 01_extract.R -- pull the two fields the WHR pipeline did not keep: the NIH RCDC spending
#' categories and the NIH-assigned PROJECT_TERMS, per APPLICATION_ID and fiscal year.
#'
#' Sources (public NIH ExPORTER / RePORTER files; place them under data/raw/{FY}/):
#'   FY2013-2025  ExPORTER project CSVs (prj.csv), columns
#'                APPLICATION_ID, NIH_SPENDING_CATS, PROJECT_TERMS
#'   FY2023       some bulk files have PROJECT_TERMS but an empty NIH_SPENDING_CATS column, so the
#'                RCDC CHD flag for FY2023 comes from the RePORTER API (step b below)
#'   FY2026       RePORTER API JSON (terms only; RCDC categories are assigned after the fiscal
#'                year closes, so none exist yet for FY2026)
#' (b) RePORTER API v2: every application id carrying RCDC category 3533 ("Congenital Heart
#'     Disease") for FY2013-2026 -- used to fill FY2023 and to cross-check the bulk files.
#' Output: data/work/extra_{FY}.rds (APPLICATION_ID, rcdc_chd, terms), data/work/api_rcdc_chd.rds
#' Investigator names are never read.
source("R/00_setup.R")
args <- commandArgs(trailingOnly = TRUE)

extract_year <- function(fy) {
  f <- wp(sprintf("extra_%d.rds", fy))
  if (file.exists(f)) return(invisible())
  if (fy %in% CONFIG$exporter_years) {
    d <- fread(file.path(CONFIG$raw_dir, fy, "prj.csv"), select = c("APPLICATION_ID", "NIH_SPENDING_CATS", "PROJECT_TERMS"),
               colClasses = "character", encoding = "Latin-1")
  } else {
    fs <- Sys.glob(file.path(CONFIG$raw_dir, fy, "raw", "*.json"))
    d <- rbindlist(lapply(fs, function(f) {
      R <- fromJSON(f, simplifyVector = FALSE)$results
      if (!length(R)) return(NULL)
      data.table(APPLICATION_ID = vapply(R, function(r) as.character(r$appl_id), ""),
                 NIH_SPENDING_CATS = vapply(R, function(r) if (is.null(r$spending_categories_desc)) NA_character_ else r$spending_categories_desc, ""),
                 PROJECT_TERMS = vapply(R, function(r) if (is.null(r$terms)) NA_character_ else r$terms, ""))
    }))
  }
  d[, rcdc_chd := hit(NIH_SPENDING_CATS, "(^|;)\\s*Congenital Heart Disease\\s*(;|$)")]
  d[, rcdc_present := !is.na(NIH_SPENDING_CATS) & NIH_SPENDING_CATS != ""]
  out <- d[, .(APPLICATION_ID, rcdc_chd, rcdc_present, terms = PROJECT_TERMS)]
  saveRDS(out, f)
  say(fy, ": ", nrow(out), " rows; RCDC populated ", round(100 * mean(out$rcdc_present), 1), "%; RCDC CHD rows ", sum(out$rcdc_chd))
}
for (fy in CONFIG$years) extract_year(fy)

# (b) API list of RCDC-CHD application ids by fiscal year (<= ~350 per year; 500 per page)
api_post <- function(body) {
  for (t in 1:5) {
    r <- tryCatch({
      h <- curl::new_handle()
      curl::handle_setopt(h, postfields = toJSON(body, auto_unbox = TRUE), timeout = 120)
      curl::handle_setheaders(h, "Content-Type" = "application/json")
      x <- curl::curl_fetch_memory(CONFIG$api_url, handle = h)
      if (x$status_code >= 400) stop("HTTP ", x$status_code)
      fromJSON(rawToChar(x$content), simplifyVector = FALSE)
    }, error = function(e) { Sys.sleep(5 * t); NULL })
    if (!is.null(r)) return(r)
  }
  stop("API failed")
}
f <- wp("api_rcdc_chd.rds")
if (!file.exists(f)) {
  A <- rbindlist(lapply(CONFIG$years, function(fy) {
    res <- list(); off <- 0; n <- Inf
    while (off < n) {
      j <- api_post(list(criteria = list(fiscal_years = list(fy),
                                         spending_categories = list(values = list(CONFIG$rcdc_chd_id), match_all = FALSE)),
                         include_fields = list("ApplId", "FiscalYear"), offset = off, limit = 500))
      n <- j$meta$total; res <- c(res, j$results); off <- off + 500; Sys.sleep(1)
    }
    say("API FY", fy, ": ", n, " RCDC CHD records")
    if (!length(res)) return(data.table(FY = fy, APPLICATION_ID = character()))
    data.table(FY = fy, APPLICATION_ID = vapply(res, function(r) as.character(r$appl_id), ""))
  }))
  attr(A, "retrieved") <- as.character(Sys.Date())
  saveRDS(A, f)
}
