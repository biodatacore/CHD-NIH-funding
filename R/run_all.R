#' run_all.R -- run every step in order from the project root: Rscript R/run_all.R
#' 01 needs network (RePORTER API) only on the first run; later runs use the cached files.
for (s in c("01_extract", "02_build", "03_classify", "04_sample", "05_analysis", "06_figures", "07_cvd", "08_wonder", "09_manual_check", "10_blind_and_key")) {
  message("== ", s); sys.source(file.path("R", paste0(s, ".R")), envir = new.env())
}
# source("R/11_score_review.R")  # run after reviewer_returned.xlsx is present
