#!/usr/bin/env Rscript
# Reproduce the v2.4 classification, funding tables, validation scores,
# share/mortality tables, and figures from the repository root.
#
#   Rscript R/run_v2.4_all.R
#
# Outputs go to outputs/v2.4/r/ by default so the shipped Python tables are
# not overwritten. Set CHD_V2_OUT and CHD_FIG_OUT to write elsewhere.
# Python remains an alternative (python3 R/14_v2_run.py, R/21_v24_shares.py,
# R/22_v24_figures.py). Do not run assemble.py.

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
if (length(file_arg)) {
  this <- normalizePath(sub("^--file=", "", file_arg[[1]]))
  root <- normalizePath(file.path(dirname(this), ".."))
  setwd(root)
}
if (file.exists("R/23_v24_classify.R")) {
  # already at root or set above
} else {
  stop("Run from the repository root: Rscript R/run_v2.4_all.R")
}

source("R/23_v24_classify.R")
source("R/chd_v24_metrics.R")
source("R/24_v24_funding.R")
source("R/25_v24_score.R")
source("R/26_v24_shares.R")
source("R/27_v24_figures.R")

out <- Sys.getenv("CHD_V2_OUT", "outputs/v2.4/r")
fig <- Sys.getenv("CHD_FIG_OUT", file.path(out, "figures_tables"))
if (!nzchar(Sys.getenv("CHD_REF_OVERRIDES"))) {
  Sys.setenv(CHD_REF_OVERRIDES = "data/validation/v2.3_reference_overrides.xlsx")
}
dir.create(out, showWarnings = FALSE, recursive = TRUE)
dir.create(fig, showWarnings = FALSE, recursive = TRUE)

cat("== v2.4 R pipeline ==\n")
cat("Loading and classifying the CHD-signal pool...\n")
pool <- load_v2_pool()
D <- chd_classify(pool, version = "2.4")
cat("  ", nrow(D), " project-years; combined ", sum(D$chd_v2), "\n", sep = "")

cat("Writing funding workbook and in-sample rescore...\n")
fund <- chd_write_funding(D, out)
ins <- chd_insample_rescore(D, out, idx_path = "data/bootstrap/boot_insample.idx.xz")

cat("Scoring V2 / V3 / V4 and the combined estimate...\n")
sc <- run_v24_scoring(D, pool = pool, out_dir = out)

cat("Shares, mortality, key numbers, v1 self-check...\n")
# Prefer the just-written funding file
sh <- run_v24_shares(out_dir = fig, funding_xlsx = file.path(out, "chd_v2_funding.xlsx"),
                     score_dir = out)

cat("Figures...\n")
run_v24_figures(out_dir = fig)

cat("\nDone. Outputs in ", out, " and ", fig, "\n", sep = "")
