#' 04_write_denominators.R -- rebuild the compact yearly tables used by the
#' v2.4 share / mortality / figure steps, from C.rds plus the shipped CVD
#' flag (the v1 / WHR broad2 definition already applied to this universe).
#'
#' Writes:
#'   data/work/nih_cvd_yearly.csv
#'   data/work/rcdc_chd_projects.csv
#'   data/work/v1_keyword_yearly.csv
#'   data/work/v1_keyword_age.csv
#'   data/work/v24_cv_flags.csv  (CVD flag for every CHD-signal pool row;
#'     R/run_all_v2.4.R later replaces this with the funding-workbook subset)

source("R/00_setup.R")

C <- data.table::as.data.table(readRDS(wp("C.rds")))
if (!"cv" %in% names(C)) {
  stop("C.rds has no cv column; run R/02_load_shipped.R so the shipped CVD flags are on G/C")
}
C[is.na(cv), cv := FALSE]

# Yearly NIH and CVD denominators, plus RCDC CHD totals in years the category exists.
D <- C[, .(
  nih_projects = .N,
  NIH_USD = sum(USD),
  CVD_projects = sum(cv %in% TRUE),
  CVD_USD = sum(USD[cv %in% TRUE]),
  rcdc_projects = sum(rcdc %in% TRUE & FY %in% 2016:2025),
  rcdc_USD = sum(USD[rcdc %in% TRUE & FY %in% 2016:2025])
), by = FY][order(FY)]

Rcdc <- C[rcdc == TRUE & FY %in% 2016:2025, .(FY, FULL_PROJECT_NUM, USD)]

K <- C[kw == TRUE, .(
  CHD_projects = .N,
  CHD_USD = sum(USD),
  CHD_in_CVD_projects = sum(cv %in% TRUE),
  CHD_in_CVD_USD = sum(USD[cv %in% TRUE]),
  CHD_not_CVD_USD = sum(USD[cv %in% FALSE])
), by = FY][order(FY)]

age_chr <- if (is.factor(C$age)) as.character(C$age) else as.character(C$age)
A <- C[kw == TRUE, .(USD = sum(USD), n = .N),
       by = .(FY, age = if (is.factor(age)) as.character(age) else as.character(age))]
A <- A[order(FY, age)]

write_py_csv <- function(d, path) {
  out <- as.data.frame(d, stringsAsFactors = FALSE)
  for (cn in names(out)) {
    v <- out[[cn]]
    if (is.logical(v)) {
      out[[cn]] <- ifelse(is.na(v), "", ifelse(v, "True", "False"))
    } else if (is.numeric(v) && !is.integer(v)) {
      out[[cn]] <- ifelse(is.na(v), "",
                          ifelse(abs(v - round(v)) < 1e-9, sprintf("%.1f", v),
                                 format(v, scientific = FALSE, trim = TRUE)))
    }
  }
  utils::write.table(out, path, sep = ",", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, na = "", fileEncoding = "UTF-8")
}

write_py_csv(D, wp("nih_cvd_yearly.csv"))
write_py_csv(Rcdc, wp("rcdc_chd_projects.csv"))
write_py_csv(K, wp("v1_keyword_yearly.csv"))
write_py_csv(A, wp("v1_keyword_age.csv"))

# CVD flags for every row of the just-written pool (covers all funding projects).
pool_path <- wp("v2_pool.tsv.xz")
if (file.exists(pool_path)) {
  con <- xzfile(pool_path, open = "rt")
  pool <- utils::read.delim(con, sep = "\t", stringsAsFactors = FALSE,
                            check.names = FALSE, quote = "\"",
                            strip.white = FALSE, na.strings = "",
                            comment.char = "")
  close(con)
  key <- paste(C$FY, C$FULL_PROJECT_NUM)
  m <- match(paste(pool$FY, pool$FULL_PROJECT_NUM), key)
  flags <- data.frame(FY = as.integer(pool$FY),
                      FULL_PROJECT_NUM = as.character(pool$FULL_PROJECT_NUM),
                      cv = C$cv[m],
                      stringsAsFactors = FALSE)
  write_py_csv(flags, wp("v24_cv_flags.csv"))
  say("wrote pool-level v24_cv_flags.csv (", nrow(flags), " rows)")
}

say("wrote nih_cvd_yearly.csv, rcdc_chd_projects.csv, v1_keyword_yearly.csv, v1_keyword_age.csv")
