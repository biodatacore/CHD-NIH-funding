# 24_v24_funding.R -- apply v2.4 rules, write the funding workbook and the
# in-sample rescore (R port of R/14_v2_run.py, DRAW_SAMPLE=0 path).
# Run from the repository root, or via Rscript R/run_v2.4_all.R.

if (!exists("chd_classify")) source("R/23_v24_classify.R")
if (!exists("chd_metr")) source("R/chd_v24_metrics.R")

chd_age_wide <- function(df, fy, age, usd, years = 2013:2026, age_levels = NULL) {
  if (is.null(age_levels)) age_levels <- sort(unique(as.character(age)))
  M <- matrix(0, length(years), length(age_levels),
              dimnames = list(as.character(years), age_levels))
  if (length(fy)) {
    tb <- tapply(usd, list(factor(fy, levels = years), factor(age, levels = age_levels)), sum, default = 0)
    tb[is.na(tb)] <- 0
    M[rownames(tb), colnames(tb)] <- tb
  }
  as.data.frame(M / 1e6, check.names = FALSE)
}

chd_write_funding <- function(D, out_dir = NULL) {
  if (is.null(out_dir)) out_dir <- Sys.getenv("CHD_V2_OUT", "outputs/v2.4")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  D$title <- chd_deidentify_title(D$title)
  kw1 <- if ("kw_v1" %in% names(D)) chd_as_logical(D$kw_v1) else chd_as_logical(D$kw)
  years <- 2013:2026
  sumM <- function(mask) {
    v <- tapply(D$USD[mask], factor(D$FY[mask], levels = years), sum, default = 0)
    v[is.na(v)] <- 0
    as.numeric(v) / 1e6
  }
  nY <- function(mask) {
    v <- as.integer(table(factor(D$FY[mask], levels = years)))
    as.integer(v)
  }
  rcdc_mask <- D$rcdc & D$FY >= 2016 & D$FY <= 2025
  Y <- data.frame(
    FY = years,
    old_keyword_M = sumM(kw1),
    tier1_M = sumM(D$tier1),
    tier2_M = sumM(D$tier2),
    combined_M = sumM(D$chd_v2),
    RCDC_M = sumM(rcdc_mask),
    tier1_n = nY(D$tier1),
    tier2_n = nY(D$tier2),
    combined_n = nY(D$chd_v2),
    old_n = nY(kw1),
    stringsAsFactors = FALSE
  )
  Y$combined_vs_old_pct <- 100 * (Y$combined_M / Y$old_keyword_M - 1)
  Y$combined_pct_of_RCDC <- 100 * Y$combined_M / Y$RCDC_M
  Y$RCDC_M[!(Y$FY %in% 2016:2025)] <- NA_real_
  Y$combined_pct_of_RCDC[!(Y$FY %in% 2016:2025)] <- NA_real_

  age_old <- as.character(D$age)
  age_old[age_old == "Basic/non-age-specific"] <- "Not age-specific"
  age_old[age_old == "Unclear"] <- "Unclear (v1 only)"
  AGE_OLD <- chd_age_wide(D, D$FY[kw1], age_old[kw1], D$USD[kw1], years,
                          c("Adult", "Both", "Not age-specific", "Pediatric", "Unclear (v1 only)"))
  AGE_NEW <- chd_age_wide(D, D$FY[D$chd_v2], D$age_v2[D$chd_v2], D$USD[D$chd_v2], years,
                          c("Adult", "Both", "Not age-specific", "Pediatric"))
  AGE_T1 <- chd_age_wide(D, D$FY[D$tier1], D$age_v2[D$tier1], D$USD[D$tier1], years,
                         c("Adult", "Both", "Not age-specific", "Pediatric"))
  share <- function(t) {
    rs <- rowSums(t)
    out <- 100 * as.data.frame(lapply(t, function(col) col / rs), check.names = FALSE)
    names(out) <- names(t)
    as.data.frame(lapply(out, function(x) chd_round(x, 1)), check.names = FALSE)
  }
  tot <- function(t) chd_round(100 * colSums(t) / sum(colSums(t)), 1)
  AGE_SUM <- data.frame(
    `v1 keyword (5-level), % of $ FY2013-2026` = tot(AGE_OLD)[c("Adult", "Both", "Not age-specific", "Pediatric", "Unclear (v1 only)")],
    `v2 tier 1, %` = c(tot(AGE_T1)[c("Adult", "Both", "Not age-specific", "Pediatric")], NA_real_),
    `v2 combined, %` = c(tot(AGE_NEW)[c("Adult", "Both", "Not age-specific", "Pediatric")], NA_real_),
    check.names = FALSE
  )
  rownames(AGE_SUM) <- c("Adult", "Both", "Not age-specific", "Pediatric", "Unclear (v1 only)")

  t2 <- D[D$tier2, , drop = FALSE]
  routes <- sort(unique(t2$t2_route))
  ROUTES <- data.frame(
    t2_route = routes,
    project_years = as.integer(sapply(routes, function(r) sum(t2$t2_route == r))),
    USD_M = as.numeric(sapply(routes, function(r) sum(t2$USD[t2$t2_route == r]) / 1e6)),
    stringsAsFactors = FALSE
  )
  drops_src <- D[D$kw & !D$tier1, , drop = FALSE]
  drop_levels <- sort(unique(drops_src$t1_drop), na.last = FALSE)
  DROPS <- data.frame(
    t1_drop = drop_levels,
    project_years = as.integer(sapply(drop_levels, function(r) sum(drops_src$t1_drop == r, na.rm = FALSE) +
                                        if (is.na(r) || r == "") sum(is.na(drops_src$t1_drop) | drops_src$t1_drop == "") else 0L)),
    USD_M = NA_real_,
    stringsAsFactors = FALSE
  )
  # cleaner aggregation
  split_drop <- ifelse(is.na(drops_src$t1_drop), "", drops_src$t1_drop)
  drop_levels <- sort(unique(split_drop))
  DROPS <- data.frame(
    t1_drop = drop_levels,
    project_years = as.integer(sapply(drop_levels, function(r) sum(split_drop == r))),
    USD_M = as.numeric(sapply(drop_levels, function(r) sum(drops_src$USD[split_drop == r]) / 1e6)),
    stringsAsFactors = FALSE
  )

  proj <- D[D$chd_v2 | D$kw, c("FY", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "IC", "ACT",
                                "USD", "title", "rcdc", "kw", "tier", "t1_drop", "t2_route",
                                "age", "age_v2"), drop = FALSE]

  # Write with unrounded dollars available, then a rounded copy for Yearly/Age.
  add_fy <- function(d) {
    data.frame(FY = years, d, check.names = FALSE, row.names = NULL)
  }
  Yw <- Y
  for (cn in c("old_keyword_M", "tier1_M", "tier2_M", "combined_M", "RCDC_M",
               "combined_vs_old_pct", "combined_pct_of_RCDC")) {
    Yw[[cn]] <- chd_round(Yw[[cn]], 2)
  }
  AGE_NEW_w <- add_fy(as.data.frame(lapply(AGE_NEW, function(x) chd_round(x, 2)), check.names = FALSE))
  AGE_T1_w <- add_fy(as.data.frame(lapply(AGE_T1, function(x) chd_round(x, 2)), check.names = FALSE))
  AGE_OLD_w <- add_fy(as.data.frame(lapply(AGE_OLD, function(x) chd_round(x, 2)), check.names = FALSE))
  ROUTES_w <- ROUTES; ROUTES_w$USD_M <- chd_round(ROUTES_w$USD_M, 2)
  DROPS_w <- DROPS; DROPS_w$USD_M <- chd_round(DROPS_w$USD_M, 2)
  AGE_pct <- add_fy(share(AGE_NEW))
  AGE_SUM_w <- data.frame(item = rownames(AGE_SUM), AGE_SUM, check.names = FALSE, row.names = NULL)
  names(AGE_SUM_w)[1] <- ""

  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("Package openxlsx is required")
  wb <- openxlsx::createWorkbook()
  add_df <- function(name, df, rowNames = FALSE) {
    openxlsx::addWorksheet(wb, name)
    openxlsx::writeData(wb, name, df, rowNames = rowNames)
  }
  add_df("Yearly", Yw)
  add_df("Age_summary", AGE_SUM_w)
  add_df("Age_USD_M_combined", AGE_NEW_w)
  add_df("Age_pct_combined", AGE_pct)
  add_df("Age_USD_M_tier1", AGE_T1_w)
  add_df("Age_USD_M_v1", AGE_OLD_w)
  add_df("Tier2_routes", ROUTES_w)
  add_df("Tier1_drops", DROPS_w)
  add_df("Projects", proj)
  path <- file.path(out_dir, "chd_v2_funding.xlsx")
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(list(Y = Y, AGE_NEW = AGE_NEW, AGE_T1 = AGE_T1, AGE_OLD = AGE_OLD,
                 AGE_SUM = AGE_SUM, ROUTES = ROUTES, DROPS = DROPS, Projects = proj,
                 path = path, D = D))
}

chd_insample_rescore <- function(D, out_dir = NULL, idx_path = "data/bootstrap/boot_insample.idx.xz") {
  if (is.null(out_dir)) out_dir <- Sys.getenv("CHD_V2_OUT", "outputs/v2.4")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  if (!requireNamespace("readxl", quietly = TRUE)) stop("Package readxl is required")
  key <- readxl::read_excel("outputs/chd_manual_check_ANSWER_KEY.xlsx", sheet = "Key_CHD")
  ret <- readxl::read_excel("outputs/reviewer_returned.xlsx", sheet = "CHD_review")
  CC <- "CHD focus (Yes / Partly / No / Unsure)"
  CA <- "Age population (Pediatric / Adult / Both / Neither / Unclear)"
  S <- merge(key[, c("Review ID", "Project number", "Fiscal year", "Stratum", "Pipeline_keyword_CHD")],
             ret[, c("Review ID", CC, CA)], by = "Review ID", all.x = TRUE, sort = FALSE)
  S$R1 <- tools::toTitleCase(tolower(trimws(as.character(S[[CC]]))))
  # capitalize like Python str.capitalize (first char only)
  cap1 <- function(x) {
    x <- trimws(as.character(x))
    ifelse(is.na(x) | !nzchar(x), x, paste0(toupper(substr(x, 1, 1)), tolower(substr(x, 2, nchar(x)))))
  }
  S$R1 <- cap1(S[[CC]])
  rc <- readxl::read_excel("outputs/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx", sheet = "Map_CHD")
  rb_path <- Sys.getenv("CHD_RECHECK_RETURNED", "data/validation/priority_recheck_returned.xlsx")
  rb <- readxl::read_excel(rb_path, sheet = "CHD_review")
  rc <- merge(rc, rb[, c("Review ID", CC, CA)], by.x = "Priority_ID", by.y = "Review ID",
              all.x = TRUE, suffixes = c("", "_r2"), sort = FALSE)
  rc$R2 <- cap1(rc[[CC]])
  o12 <- rc[rc$Internal_Tier %in% c(1, 2) & rc$R2 != "Unsure", ]
  map12 <- o12$R2; names(map12) <- as.character(o12$Round1_Review_ID)
  S$Final <- ifelse(as.character(S$`Review ID`) %in% names(map12),
                    unname(map12[as.character(S$`Review ID`)]), S$R1)
  ov <- Sys.getenv("CHD_REF_OVERRIDES", unset = "")
  if (nzchar(ov) && file.exists(ov)) {
    o <- readxl::read_excel(ov, sheet = "Overrides")
    o <- o[grepl("^v1", as.character(o$review)), ]
    mo <- o$`new label`; names(mo) <- as.character(o$`Review ID`)
    hit <- as.character(S$`Review ID`) %in% names(mo)
    S$Final[hit] <- unname(mo[as.character(S$`Review ID`)[hit]])
  }
  oa <- rc[rc$Internal_Tier == 3, ]
  mapa <- oa[[CA]]; names(mapa) <- as.character(oa$Round1_Review_ID)
  S$Final_age <- ifelse(as.character(S$`Review ID`) %in% names(mapa),
                        unname(mapa[as.character(S$`Review ID`)]), S[[CA]])
  kw1 <- if ("kw_v1" %in% names(D)) chd_as_logical(D$kw_v1) else chd_as_logical(D$kw)
  lab <- D[, c("FY", "FULL_PROJECT_NUM", "kw", "tier1", "tier2", "chd_v2", "tier", "age_v2", "title")]
  lab$kw <- kw1
  S <- merge(S, lab, by.x = c("Fiscal year", "Project number"),
             by.y = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE, sort = FALSE)
  for (cn in c("kw", "tier1", "tier2", "chd_v2")) {
    S[[cn]] <- chd_as_logical(S[[cn]])
    S[[cn]][is.na(S[[cn]])] <- FALSE
  }
  SIZES <- c(`Keyword CHD (all unique cores)` = 690,
             `RCDC only (not keyword)` = 459,
             `Near-miss negative (1-2 strong terms)` = 429)
  ns <- table(S$Stratum)
  S$w <- as.numeric(SIZES[as.character(S$Stratum)] / as.numeric(ns[as.character(S$Stratum)]))
  # Preserve merge order as close as possible to pandas (key left, then ret).
  # pandas merge keeps left key order. key read_excel order should be used.
  # Re-merge using key row order:
  # Already merged with sort=FALSE from key-based first merge? The first merge
  # used key as left with sort=FALSE, then later merge may shuffle.
  # Restore key order:
  key_order <- as.character(key$`Review ID`)
  S <- S[match(key_order, as.character(S$`Review ID`)), ]
  if (anyNA(S$`Review ID`)) stop("in-sample merge lost review IDs")

  truths <- list(`Yes|Partly` = S$Final %in% c("Yes", "Partly"), `Yes only` = S$Final == "Yes")
  defs <- list(`v1 keyword` = S$kw, `v2 tier 1` = S$tier1, `v2 combined (tier 1 + 2)` = S$chd_v2)
  weights <- list(unweighted = rep(1, nrow(S)), weighted = S$w)
  st <- as.character(S$Stratum)
  idx <- if (file.exists(idx_path)) read_boot_idx(idx_path) else NULL
  rows <- list(); k <- 1L
  for (tn in names(truths)) {
    rp <- truths[[tn]]
    for (dn in names(defs)) {
      pp <- defs[[dn]]
      for (wn in names(weights)) {
        w <- weights[[wn]]
        m <- chd_metr(pp, rp, w)
        q <- chd_boot_quantiles(pp, rp, w, st, idx = idx, idx_path = if (is.null(idx)) idx_path else NULL)
        if (is.null(idx)) idx <- q$idx
        for (met in c("Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa")) {
          rows[[k]] <- data.frame(Label = "IN-SAMPLE (development data)",
                                  `Reviewer CHD =` = tn, Definition = dn, Weighting = wn,
                                  Metric = met, Estimate = m[[met]],
                                  CI_low = unname(q$lo[met]), CI_high = unname(q$hi[met]),
                                  check.names = FALSE, stringsAsFactors = FALSE)
          k <- k + 1L
        }
        tpfn <- paste(sprintf("%.0f", c(m$TP, m$FP, m$FN, m$TN)), collapse = "/")
        rows[[k]] <- data.frame(Label = "IN-SAMPLE (development data)",
                                `Reviewer CHD =` = tn, Definition = dn, Weighting = wn,
                                Metric = "TP/FP/FN/TN", Estimate = tpfn,
                                CI_low = NA_real_, CI_high = NA_real_,
                                check.names = FALSE, stringsAsFactors = FALSE)
        k <- k + 1L
      }
    }
  }
  IS <- do.call(rbind, rows)
  amap <- c(Neither = "Not age-specific", `Neither / not age-specific` = "Not age-specific")
  A <- S[S$chd_v2 & S$Final %in% c("Yes", "Partly"), ]
  A$rev_age <- as.character(A$Final_age)
  A$rev_age[A$rev_age %in% names(amap)] <- unname(amap[A$rev_age[A$rev_age %in% names(amap)]])
  A <- A[A$rev_age %in% c("Pediatric", "Adult", "Both", "Not age-specific"), ]
  po <- mean(A$rev_age == A$age_v2)
  ct <- table(factor(A$rev_age, levels = c("Adult", "Both", "Not age-specific", "Pediatric")),
              factor(A$age_v2, levels = c("Adult", "Both", "Not age-specific", "Pediatric")))
  pe <- sum(rowSums(ct) * colSums(ct)) / nrow(A)^2
  AG <- data.frame(Item = "IN-SAMPLE age (v2 4-level) vs reviewer, CHD-positive rows with a definite reviewer age",
                   n = nrow(A), Agreement = po, Kappa = (po - pe) / (1 - pe),
                   stringsAsFactors = FALSE)
  DIS <- S[S$chd_v2 != (S$Final %in% c("Yes", "Partly")),
           c("Review ID", "Project number", "Fiscal year", "Stratum", "title", "tier", "Final")]
  note <- data.frame(NOTE = c(
    "IN-SAMPLE CHECK ONLY. The 833-grant sample (and its 36 confirmed misses / 9 confirmed false positives) was used to develop the v2 rules, so these metrics are optimistic. Use the fresh 200-grant set for out-of-sample validation.",
    "Weighted = inverse-probability weights to the v1 sampling frame (keyword 690/689, RCDC-only 459/95, near-miss 429/49); 95% CI = stratified bootstrap (2,000 draws). The frame excludes NIH grants with no CHD signal."
  ), stringsAsFactors = FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "README"); openxlsx::writeData(wb, "README", note)
  openxlsx::addWorksheet(wb, "Metrics"); openxlsx::writeData(wb, "Metrics", IS)
  openxlsx::addWorksheet(wb, "Age"); openxlsx::writeData(wb, "Age", AG)
  openxlsx::addWorksheet(wb, "Age_confusion"); openxlsx::writeData(wb, "Age_confusion", as.data.frame.matrix(ct), rowNames = TRUE)
  openxlsx::addWorksheet(wb, "Disagreements"); openxlsx::writeData(wb, "Disagreements", DIS)
  path <- file.path(out_dir, "chd_v2_insample_rescore.xlsx")
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(list(IS = IS, AG = AG, DIS = DIS, ct = ct, S = S, path = path, idx = idx))
}

run_v24_funding <- function(out_dir = NULL, pool_path = NULL) {
  if (is.null(out_dir)) out_dir <- Sys.getenv("CHD_V2_OUT", "outputs/v2.4")
  D <- chd_classify(load_v2_pool(pool_path), version = "2.4")
  fund <- chd_write_funding(D, out_dir)
  ins <- chd_insample_rescore(D, out_dir)
  invisible(list(D = D, fund = fund, ins = ins))
}

if (identical(environment(), globalenv()) && !interactive() &&
    any(grepl("24_v24_funding\\.R$", commandArgs(trailingOnly = FALSE)))) {
  setwd(chd_root())
  run_v24_funding()
}
