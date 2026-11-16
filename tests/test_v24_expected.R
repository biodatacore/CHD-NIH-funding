#!/usr/bin/env Rscript
#' tests/test_v24_expected.R -- expected-value checks for a from-scratch
#' R rebuild (Rscript R/run_all_v2.4.R).
#'
#' Compares rebuilt data/work tables and the v2.4 shares workbook against
#' tests/expected_values.csv and tests/expected_key_numbers.csv.
#' Prints PASS/FAIL per check and an OVERALL line. Exit status 1 on failure.
#'
#' Usage (from the repository root):
#'   Rscript tests/test_v24_expected.R
#'   CHD_FIG_OUT=outputs/v2.4/r/figures_tables Rscript tests/test_v24_expected.R

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
if (length(file_arg)) {
  this <- normalizePath(sub("^--file=", "", file_arg[[1]]))
  root <- normalizePath(file.path(dirname(this), ".."))
  setwd(root)
}
if (!file.exists("tests/expected_values.csv")) {
  stop("Run from the repository root: Rscript tests/test_v24_expected.R")
}

fig <- Sys.getenv("CHD_FIG_OUT", "outputs/v2.4/r/figures_tables")
out_v2 <- Sys.getenv("CHD_V2_OUT", "outputs/v2.4/r")

as_bool <- function(x) {
  if (is.logical(x)) { x[is.na(x)] <- FALSE; return(x) }
  y <- tolower(as.character(x))
  out <- y %in% c("true", "t", "1")
  out[is.na(x) | !nzchar(y)] <- FALSE
  out
}

read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  strip.white = FALSE, na.strings = c("", "NA"))
}

num_or_na <- function(x) {
  if (is.numeric(x)) return(as.numeric(x))
  v <- suppressWarnings(as.numeric(as.character(x)))
  v
}

# ---- observed values from rebuilt tables -----------------------------------
obs <- list()
den <- read_csv("data/work/nih_cvd_yearly.csv")
v1y <- read_csv("data/work/v1_keyword_yearly.csv")
v1a <- read_csv("data/work/v1_keyword_age.csv")
rcdc <- read_csv("data/work/rcdc_chd_projects.csv")
flags <- read_csv("data/work/v24_cv_flags.csv")
wonder <- read_csv("data/wonder/wonder_long.csv")

pool_n <- NA_integer_
if (file.exists("data/work/v2_pool.tsv.xz")) {
  con <- xzfile("data/work/v2_pool.tsv.xz", open = "rt")
  pool <- utils::read.delim(con, sep = "\t", stringsAsFactors = FALSE,
                            check.names = FALSE, quote = "\"",
                            strip.white = FALSE, na.strings = "",
                            comment.char = "")
  close(con)
  pool_n <- nrow(pool)
} else if (file.exists("data/work/v2_pool.rds")) {
  pool_n <- nrow(readRDS("data/work/v2_pool.rds"))
}

g_n <- if (file.exists("data/work/G.rds")) nrow(readRDS("data/work/G.rds")) else NA_integer_
c_path <- "data/work/C.rds"
cv_true <- NA_integer_
if (file.exists(c_path)) {
  C <- readRDS(c_path)
  if ("cv" %in% names(C)) cv_true <- sum(C$cv %in% TRUE)
}

obs$universe_project_years <- g_n
obs$pool_project_years <- pool_n
obs$rcdc_chd_project_years <- nrow(rcdc)
obs$v24_cv_flags_rows <- nrow(flags)
obs$v1_keyword_yearly_rows <- nrow(v1y)
obs$v1_keyword_age_rows <- nrow(v1a)
obs$wonder_long_rows <- nrow(wonder)
obs$cvd_true_project_years <- cv_true
obs$nih_projects_2013_check <- den$nih_projects[den$FY == 2013]
obs$CVD_projects_2013_check <- den$CVD_projects[den$FY == 2013]
for (i in seq_len(nrow(den))) {
  fy <- den$FY[i]
  obs[[paste0("nih_projects_", fy)]] <- den$nih_projects[i]
  obs[[paste0("NIH_USD_", fy)]] <- den$NIH_USD[i]
  obs[[paste0("CVD_projects_", fy)]] <- den$CVD_projects[i]
  obs[[paste0("CVD_USD_", fy)]] <- den$CVD_USD[i]
  obs[[paste0("rcdc_projects_", fy)]] <- den$rcdc_projects[i]
  obs[[paste0("rcdc_USD_", fy)]] <- den$rcdc_USD[i]
}
for (i in seq_len(nrow(v1y))) {
  fy <- v1y$FY[i]
  obs[[paste0("v1_CHD_projects_", fy)]] <- v1y$CHD_projects[i]
  obs[[paste0("v1_CHD_USD_", fy)]] <- v1y$CHD_USD[i]
  obs[[paste0("v1_CHD_in_CVD_projects_", fy)]] <- v1y$CHD_in_CVD_projects[i]
  obs[[paste0("v1_CHD_in_CVD_USD_", fy)]] <- v1y$CHD_in_CVD_USD[i]
  obs[[paste0("v1_CHD_not_CVD_USD_", fy)]] <- v1y$CHD_not_CVD_USD[i]
}

# Headlines and counts from the shares workbook, if present.
xlsx <- file.path(fig, "chd_v2.4_shares_mortality.xlsx")
fund <- file.path(out_v2, "chd_v2_funding.xlsx")
if (file.exists(fund)) {
  proj <- openxlsx::read.xlsx(fund, sheet = "Projects")
  if ("tier" %in% names(proj)) {
    obs$v24_combined_project_years <- sum(proj$tier %in% c(
      "Tier 1 CHD-focused", "Tier 2 CHD-related basic/developmental"))
    obs$v24_tier1_project_years <- sum(proj$tier == "Tier 1 CHD-focused")
    obs$v24_tier2_project_years <- sum(proj$tier == "Tier 2 CHD-related basic/developmental")
  }
}
if (file.exists(xlsx)) {
  kn <- openxlsx::read.xlsx(xlsx, sheet = "Key_numbers")
  pick <- function(item) {
    w <- kn$item == item
    if (!any(w)) return(NA_real_)
    num_or_na(kn$value[which(w)[1]])
  }
  obs$v24_chd_usd_m_fy2013 <- pick("CHD dollars FY2013")
  obs$v24_chd_n_fy2013 <- pick("CHD project-years FY2013")
  obs$v24_chd_usd_m_fy2023 <- pick("CHD dollars FY2023")
  obs$v24_chd_n_fy2023 <- pick("CHD project-years FY2023")
  obs$v24_chd_usd_m_fy2025 <- pick("CHD dollars FY2025")
  obs$v24_chd_n_fy2025 <- pick("CHD project-years FY2025")
  obs$v24_chd_usd_apc <- pick("CHD dollars APC")
  obs$v24_chd_usd_cagr <- pick("CHD dollars CAGR")
  obs$v24_chd_usd_apc_p <- pick("CHD dollars APC p")
  obs$v24_chd_pct_cvd_apc <- pick("CHD % of NIH CVD (nested) APC")
  obs$v24_chd_pct_nih_apc <- pick("CHD % of all NIH APC")
}

# ---- expected_values.csv ----------------------------------------------------
E <- read_csv("tests/expected_values.csv")
status <- character(nrow(E))
diff <- rep(NA_real_, nrow(E))
got <- rep(NA_real_, nrow(E))
for (i in seq_len(nrow(E))) {
  id <- E$id[i]
  exp <- as.numeric(E$expected[i])
  tol <- as.numeric(E$tolerance[i])
  if (is.na(tol)) tol <- 0
  val <- obs[[id]]
  if (is.null(val) || length(val) == 0 || all(is.na(val))) {
    status[i] <- "MISSING"
    got[i] <- NA_real_
  } else {
    val <- as.numeric(val[[1]])
    got[i] <- val
    d <- val - exp
    diff[i] <- d
    status[i] <- if (abs(d) <= tol + 1e-12) "PASS" else "FAIL"
  }
}
V <- data.frame(id = E$id, expected = E$expected, value = got, diff = diff,
                tolerance = E$tolerance, status = status, stringsAsFactors = FALSE)
cat("=== expected_values.csv ===\n")
# Print failures and a short summary; full table is long.
fail <- V[V$status != "PASS", ]
if (nrow(fail)) print(fail, row.names = FALSE)
cat("SUMMARY expected_values:", paste(names(table(V$status)), table(V$status), collapse = ", "),
    " of ", nrow(V), "\n", sep = "")

# ---- 546 key numbers --------------------------------------------------------
kn_status <- data.frame()
if (file.exists(xlsx) && file.exists("tests/expected_key_numbers.csv")) {
  expk <- read_csv("tests/expected_key_numbers.csv")
  kn <- openxlsx::read.xlsx(xlsx, sheet = "Key_numbers")
  norm <- function(x) {
    x <- as.character(x)
    x[is.na(x) | x %in% c("", "NA", "NaN")] <- ""
    x
  }
  kn$key <- paste(norm(kn$section), norm(kn$item), norm(kn$window), sep = " | ")
  expk$key <- paste(norm(expk$section), norm(expk$item), norm(expk$window), sep = " | ")
  m <- merge(expk, kn[, c("key", "value")], by = "key", all.x = TRUE,
             suffixes = c("_expected", "_got"), sort = FALSE)
  # Coerce both sides: numeric when possible, else string equality
  st <- character(nrow(m))
  dv <- rep(NA_real_, nrow(m))
  got_col <- if ("value_got" %in% names(m)) "value_got" else "value"
  exp_col <- if ("value_expected" %in% names(m)) "value_expected" else setdiff(c("value", "value.x"), got_col)[1]
  for (i in seq_len(nrow(m))) {
    e <- m[[exp_col]][i]
    g <- m[[got_col]][i]
    if (is.null(g) || length(g) == 0 || (is.atomic(g) && is.na(g) && !is.na(e) && nzchar(as.character(e)))) {
      # missing observed
      en <- suppressWarnings(as.numeric(e))
      if (is.na(e) || (is.character(e) && !nzchar(e))) {
        st[i] <- if (is.na(g) || (is.character(g) && !nzchar(as.character(g)))) "PASS" else "FAIL"
        dv[i] <- 0
      } else {
        st[i] <- "MISSING"
      }
      next
    }
    en <- suppressWarnings(as.numeric(e))
    gn <- suppressWarnings(as.numeric(g))
    if (!is.na(en) && !is.na(gn)) {
      dv[i] <- gn - en
      st[i] <- if (abs(dv[i]) <= 1e-9) "PASS" else "FAIL"
    } else {
      es <- trimws(as.character(e)); gs <- trimws(as.character(g))
      if (identical(es, "NA")) es <- ""
      if (identical(gs, "NA") || is.na(g)) gs <- ""
      st[i] <- if (identical(es, gs)) "PASS" else "FAIL"
      dv[i] <- if (st[i] == "PASS") 0 else NA_real_
    }
  }
  kn_status <- data.frame(key = m$key, expected = m[[exp_col]], value = m[[got_col]],
                          diff = dv, status = st, stringsAsFactors = FALSE)
  cat("\n=== expected_key_numbers.csv (Key_numbers sheet) ===\n")
  kfail <- kn_status[kn_status$status != "PASS", ]
  if (nrow(kfail)) {
    print(utils::head(kfail, 30), row.names = FALSE)
    if (nrow(kfail) > 30) cat("  ...", nrow(kfail) - 30, " more\n")
  }
  cat("SUMMARY key_numbers:", paste(names(table(kn_status$status)), table(kn_status$status), collapse = ", "),
      " of ", nrow(kn_status), "\n", sep = "")
} else {
  cat("\nKey_numbers workbook not found at ", xlsx, " (skipping 546-row check)\n", sep = "")
}

# ---- v1 self-check text -----------------------------------------------------
sc <- file.path(fig, "self_check_v1.txt")
self_ok <- NA
if (file.exists(sc)) {
  txt <- paste(readLines(sc, warn = FALSE), collapse = "\n")
  self_ok <- grepl("ALL CHECKS PASSED", txt, fixed = TRUE)
  cat("\n=== v1 self-check ===\n")
  cat(if (isTRUE(self_ok)) "PASS: ALL CHECKS PASSED\n" else "FAIL: self-check did not report ALL CHECKS PASSED\n")
}

# ---- OVERALL ----------------------------------------------------------------
n_pass <- sum(V$status == "PASS")
n_fail <- sum(V$status != "PASS")
if (nrow(kn_status)) {
  n_pass <- n_pass + sum(kn_status$status == "PASS")
  n_fail <- n_fail + sum(kn_status$status != "PASS")
}
if (!is.na(self_ok)) {
  if (isTRUE(self_ok)) n_pass <- n_pass + 1L else n_fail <- n_fail + 1L
}
overall <- if (n_fail == 0) "PASS" else "FAIL"
cat("\nOVERALL: ", overall, "  (", n_pass, " PASS, ", n_fail, " FAIL)\n", sep = "")
dir.create("outputs/v2.4/r", showWarnings = FALSE, recursive = TRUE)
utils::write.csv(V, "outputs/v2.4/r/verification_report.csv", row.names = FALSE)
if (nrow(kn_status)) {
  utils::write.csv(kn_status, "outputs/v2.4/r/verification_key_numbers.csv", row.names = FALSE)
}
if (overall != "PASS" && !interactive()) quit(status = 1)
