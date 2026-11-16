#!/usr/bin/env Rscript
# Rebuild every v2.4 output from the shipped, de-identified NIH universe
# and WONDER XML in this repository (no ExPORTER bulk files, no network).
#
#   Rscript R/run_all_v2.4.R
#
# Steps: load data/shipped/ -> G.rds -> classify (C.rds) -> CHD-signal pool
# -> NIH/CVD denominators, RCDC list, v1 keyword tables -> WONDER long
# table -> v2.4 classification, funding, scores, shares, figures.
# Default v2.4 outputs go to outputs/v2.4/r/ so the shipped Python tables
# are not overwritten. Do not run assemble.py.

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
if (length(file_arg)) {
  this <- normalizePath(sub("^--file=", "", file_arg[[1]]))
  root <- normalizePath(file.path(dirname(this), ".."))
  setwd(root)
}
if (!file.exists("R/23_v24_classify.R")) {
  stop("Run from the repository root: Rscript R/run_all_v2.4.R")
}

t0 <- proc.time()[["elapsed"]]
step <- function(label) {
  message(sprintf("== %s  (%.1f min elapsed)", label,
                  (proc.time()[["elapsed"]] - t0) / 60))
}

step("Load shipped NIH universe and candidate text")
source("R/02_load_shipped.R")

step("Classify v1 keyword / age flags (C.rds)")
source("R/03_classify.R")

step("Rebuild the CHD-signal pool")
source("R/13a_v2_pool.R")

step("NIH / CVD denominators, RCDC list, v1 keyword tables")
source("R/04_write_denominators.R")

step("CDC WONDER long table from shipped XML")
Sys.setenv(CHD_WONDER_PARSE_ONLY = "1")
source("R/08_wonder.R")

# ---- v2.4 pipeline (same steps as R/run_v2.4_all.R), with CVD flags
# written from the just-built funding Projects sheet before shares run.
if (!nzchar(Sys.getenv("CHD_REF_OVERRIDES"))) {
  Sys.setenv(CHD_REF_OVERRIDES = "data/validation/v2.3_reference_overrides.xlsx")
}
out <- Sys.getenv("CHD_V2_OUT", "outputs/v2.4/r")
fig <- Sys.getenv("CHD_FIG_OUT", file.path(out, "figures_tables"))
dir.create(out, showWarnings = FALSE, recursive = TRUE)
dir.create(fig, showWarnings = FALSE, recursive = TRUE)

source("R/23_v24_classify.R")
source("R/chd_v24_metrics.R")
source("R/24_v24_funding.R")
source("R/25_v24_score.R")
source("R/26_v24_shares.R")
source("R/27_v24_figures.R")

step("v2.4 classify, funding workbook, scores")
pool <- load_v2_pool()
D <- chd_classify(pool, version = "2.4")
cat("  ", nrow(D), " project-years; combined ", sum(D$chd_v2), "\n", sep = "")

fund <- chd_write_funding(D, out)
ins <- chd_insample_rescore(D, out, idx_path = "data/bootstrap/boot_insample.idx.xz")
sc <- run_v24_scoring(D, pool = pool, out_dir = out)

# Replace the pool-level flag file with the funding-workbook subset
# (same 2,860 project-years as the shipped v24_cv_flags.csv).
C <- readRDS(file.path("data/work", "C.rds"))
write_funding_cv_flags <- function(funding_xlsx, C, path = "data/work/v24_cv_flags.csv") {
  proj <- openxlsx::read.xlsx(funding_xlsx, sheet = "Projects")
  key <- paste(C$FY, C$FULL_PROJECT_NUM)
  m <- match(paste(proj$FY, proj$FULL_PROJECT_NUM), key)
  if (any(is.na(m))) {
    stop("C.rds missing ", sum(is.na(m)), " funding project-years")
  }
  flags <- data.frame(
    FY = as.integer(proj$FY),
    FULL_PROJECT_NUM = as.character(proj$FULL_PROJECT_NUM),
    cv = ifelse(C$cv[m] %in% TRUE, "True", "False"),
    stringsAsFactors = FALSE
  )
  utils::write.table(flags, path, sep = ",", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(flags)
}
funding_xlsx <- file.path(out, "chd_v2_funding.xlsx")
nflags <- nrow(write_funding_cv_flags(funding_xlsx, C))
cat("Wrote data/work/v24_cv_flags.csv (", nflags, " funding project-years)\n", sep = "")

step("Shares, mortality, key numbers, v1 self-check")
sh <- run_v24_shares(out_dir = fig, funding_xlsx = funding_xlsx, score_dir = out)

step("Figures")
run_v24_figures(out_dir = fig)

elapsed <- (proc.time()[["elapsed"]] - t0) / 60
cat("\nDone in ", sprintf("%.1f", elapsed), " min. Outputs in ", out,
    " and ", fig, "\n", sep = "")
cat("Run Rscript tests/test_v24_expected.R to check expected values.\n")
