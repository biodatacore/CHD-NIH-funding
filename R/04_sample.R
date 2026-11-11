#' 04_sample.R -- draw the random validation samples (seeded) and export them for manual review.
#'   S1 precision of keyword CHD: 50 keyword-positive project-years (1 per core project)
#'   S2 RCDC-only: 25 RCDC-positive, keyword-negative project-years
#'   S3 near misses: 25 keyword-negative, non-RCDC project-years with 1-2 strong CHD mentions
#'   S4 age split: 10 keyword-CHD project-years per age category (50)
#' Reviewer judgments are entered in data/validation/review_*.csv (columns id, judge).
source("R/00_setup.R")
C <- readRDS(wp("C.rds")); set.seed(CONFIG$seed)
one <- function(d, n) { d <- d[sample(.N)][!duplicated(CORE_PROJECT_NUM)]; d[seq_len(min(n, .N))] }
S <- rbind(one(C[kw == TRUE], 50)[, set := "S1_kw"],
           one(C[rcdc & !kw], 25)[, set := "S2_rcdc_only"],
           one(C[!kw & !rcdc & s_str %in% 1:2], 25)[, set := "S3_near_miss"],
           C[kw == TRUE][sample(.N)][!duplicated(CORE_PROJECT_NUM)][, .SD[seq_len(min(10, .N))], by = age][, set := "S4_age"], fill = TRUE)
S[, id := sprintf("%s_%03d", set, seq_len(.N)), by = set]
# attach text (from the WHR project tables) for review only; never written to outputs
S[, text := {
  out <- character(.N)
  for (fy in unique(FY)) { P <- readRDS(file.path(CONFIG$whr_work, "proj", sprintf("proj_%d.rds", fy)))
    i <- which(FY == fy); out[i] <- P$text[match(FULL_PROJECT_NUM[i], P$FULL_PROJECT_NUM)] }
  out }]
dir.create("data/validation", showWarnings = FALSE)
saveRDS(S, wp("sample.rds"))
sink(wp("sample_review.txt"))
for (k in seq_len(nrow(S))) with(S[k], cat(sprintf("\n## %s FY%d %s %s $%.2fM rcdc=%s kw=%s s=%d w=%d ped=%d adu=%d basic=%d AGE=%s\nTITLE: %s\nTEXT: %s\n",
  id, FY, IC, ACT, USD / 1e6, rcdc, kw, s_str, s_weak, s_ped, s_adu, s_basic, age, title, substr(text, 1, 900))))
sink()
