#' 00_setup.R -- packages, config and small helpers shared by every step.
suppressPackageStartupMessages({
  library(data.table); library(stringi); library(jsonlite); library(readxl)
  library(ggplot2); library(openxlsx)
})
source("config.R")
dir.create(CONFIG$work_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$out_dir, "figures"), recursive = TRUE, showWarnings = FALSE)
say <- function(...) message(format(Sys.time(), "%H:%M:%S "), ...)
wp  <- function(...) file.path(CONFIG$work_dir, ...)
#' TRUE where regex p (case-insensitive ICU; inputs are lower-cased by the caller or by hit()) matches x; NA -> FALSE.
hit <- function(x, p) { h <- stri_detect_regex(stri_trans_tolower(x), p); h[is.na(h)] <- FALSE; h }
#' number of non-overlapping matches of p in x.
cnt <- function(x, p) { n <- stri_count_regex(x, p); n[is.na(n)] <- 0L; n }
