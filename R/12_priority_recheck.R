#' 12_priority_recheck.R — priority-only blind recheck (~100-150 highest-impact disagreements).
source("R/00_setup.R")
say("Running R/12_priority_recheck.py ...")
# Note: rebuild script is embedded; re-run the latest Python builder if present as 12.
rc <- system2("python3", "R/12_priority_recheck_build.py")
if (!identical(rc, 0L)) {
  # fallback: the one-shot builder may live as 12_priority_recheck.py from prior run
  rc <- system2("python3", "-c", "print(\"use R/12_priority_recheck_build.py\")")
}
say("done: outputs/chd_manual_recheck_PRIORITY_BLIND.xlsx")
