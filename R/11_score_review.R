#' 11_score_review.R — score returned blind review; flag disagreements; build round-2 recheck.
#' Implementation is Python (openpyxl) for robust Excel handling; this driver runs it.
source("R/00_setup.R")
say("Running R/11_score_review.py ...")
rc <- system2("python3", "R/11_score_review.py")
if (!identical(rc, 0L)) stop("11_score_review.py failed with code ", rc)
say("done: outputs/chd_review_scoring.xlsx")
say("done: outputs/chd_manual_recheck_round2_BLIND.xlsx")
say("done: outputs/chd_manual_recheck_round2_ANSWER_KEY.xlsx")
