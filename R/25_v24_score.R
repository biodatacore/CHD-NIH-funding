# 25_v24_score.R -- R port of 15/16/18/20 scoring and the v2.4 vs v2.3 label-change tables.
if (!exists("chd_classify")) source("R/23_v24_classify.R")
if (!exists("chd_metr")) source("R/chd_v24_metrics.R")

chd_cap1 <- function(x) {
  x <- trimws(as.character(x))
  ifelse(is.na(x) | !nzchar(x), x,
         paste0(toupper(substr(x, 1, 1)), tolower(substr(x, 2, nchar(x)))))
}

chd_read_xlsx <- function(path, sheet) {
  readxl::read_excel(path, sheet = sheet)
}

chd_relabel_key <- function(K, D, cols = c("tier", "t2_route", "age_v2", "t1_drop")) {
  cols <- intersect(cols, names(D))
  drop <- intersect(cols, names(K))
  if (length(drop)) K <- K[, setdiff(names(K), drop), drop = FALSE]
  lab <- D[, c("FY", "FULL_PROJECT_NUM", cols), drop = FALSE]
  left_ids <- if ("Review ID" %in% names(K)) as.character(K$`Review ID`) else NULL
  K <- merge(K, lab, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE, sort = FALSE)
  if (!is.null(left_ids)) K <- K[match(left_ids, as.character(K$`Review ID`)), ]
  if ("tier" %in% names(K)) {
    K$tier <- as.character(K$tier)
    K$tier[is.na(K$tier)] <- "Not CHD"
  }
  K
}

chd_apply_v1_overrides <- function(ids, labels, ov_path = Sys.getenv("CHD_REF_OVERRIDES", "")) {
  if (!nzchar(ov_path) || !file.exists(ov_path)) return(labels)
  o <- chd_read_xlsx(ov_path, "Overrides")
  o <- o[grepl("^v1", as.character(o$review)), ]
  mo <- o$`new label`; names(mo) <- as.character(o$`Review ID`)
  hit <- as.character(ids) %in% names(mo)
  labels[hit] <- unname(mo[as.character(ids)[hit]])
  labels
}

# Generic 15-style scorer.
chd_score_review <- function(key, returned, D, out_path, idx_path,
                             cc = "CHD focus (Yes / Partly / No / Unsure)",
                             ca = "Age population (Pediatric / Adult / Both / Neither / Unclear)",
                             extra_sheets = NULL) {
  K <- chd_relabel_key(key, D)
  keep_r <- intersect(c("Review ID", "Project number", cc, ca, "Comments"), names(returned))
  X0 <- merge(K, returned[, keep_r, drop = FALSE], by = "Review ID", all.x = TRUE, sort = FALSE)
  # restore key order
  X0 <- X0[match(as.character(key$`Review ID`), as.character(X0$`Review ID`)), ]
  X0$rev <- chd_cap1(X0[[cc]])
  done <- X0$rev %in% c("Yes", "Partly", "No")
  X <- X0[done, , drop = FALSE]
  X$pp <- X$tier != "Not CHD"
  st <- as.character(X$stratum)
  idx <- if (file.exists(idx_path)) read_boot_idx(idx_path) else NULL
  truths <- list(`Yes|Partly` = X$rev %in% c("Yes", "Partly"), `Yes only` = X$rev == "Yes")
  weights <- list(unweighted = rep(1, nrow(X)), weighted = as.numeric(X$weight))
  rows <- list(); k <- 1L
  for (tn in names(truths)) {
    rp <- truths[[tn]]
    for (wn in names(weights)) {
      w <- weights[[wn]]
      m <- chd_metr(X$pp, rp, w)
      q <- chd_boot_quantiles(X$pp, rp, w, st, idx = idx, idx_path = if (is.null(idx)) idx_path else NULL)
      if (is.null(idx)) idx <- q$idx
      den <- c(Sensitivity = m$TP + m$FN, Specificity = m$TN + m$FP,
               PPV = m$TP + m$FP, NPV = m$TN + m$FN, Accuracy = length(rp))
      for (met in c("Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa")) {
        if (wn == "unweighted" && met != "Kappa") {
          lohi <- chd_wilson(m[[met]] * den[[met]], den[[met]])
        } else {
          lohi <- c(unname(q$lo[met]), unname(q$hi[met]))
        }
        rows[[k]] <- data.frame(`Reviewer CHD =` = tn, Weighting = wn, Metric = met,
                                Estimate = m[[met]], CI_low = lohi[1], CI_high = lohi[2],
                                check.names = FALSE, stringsAsFactors = FALSE)
        k <- k + 1L
      }
      rows[[k]] <- data.frame(`Reviewer CHD =` = tn, Weighting = wn, Metric = "TP/FP/FN/TN",
                              Estimate = paste(sprintf("%.1f", c(m$TP, m$FP, m$FN, m$TN)), collapse = "/"),
                              CI_low = NA_real_, CI_high = NA_real_,
                              check.names = FALSE, stringsAsFactors = FALSE)
      k <- k + 1L
    }
  }
  S <- do.call(rbind, rows)
  # By_stratum
  strata <- unique(as.character(X$stratum))
  BY <- do.call(rbind, lapply(strata, function(s) {
    g <- X[X$stratum == s, ]
    data.frame(stratum = s, n = nrow(g),
               `rev_Yes|Partly` = sum(g$rev %in% c("Yes", "Partly")),
               `pct_Yes|Partly` = mean(g$rev %in% c("Yes", "Partly")),
               weight = g$weight[1], check.names = FALSE, stringsAsFactors = FALSE)
  }))
  amap <- c(Neither = "Not age-specific")
  A <- X[X$pp & X$rev %in% c("Yes", "Partly"), , drop = FALSE]
  if (ca %in% names(A)) {
    A$rev_age <- as.character(A[[ca]])
    A$rev_age[A$rev_age %in% names(amap)] <- unname(amap[A$rev_age[A$rev_age %in% names(amap)]])
    A_use <- A[A$rev_age %in% c("Pediatric", "Adult", "Both", "Not age-specific"), ]
  } else A_use <- A[0, ]
  if (nrow(A_use)) {
    po <- mean(A_use$rev_age == A_use$age_v2)
    lv <- c("Adult", "Both", "Not age-specific", "Pediatric")
    ct <- table(factor(A_use$rev_age, levels = lv), factor(A_use$age_v2, levels = lv))
    pe <- sum(rowSums(ct) * colSums(ct)) / nrow(A_use)^2
    kappa <- if (pe < 1) (po - pe) / (1 - pe) else NA_real_
  } else {
    po <- NA_real_; kappa <- NA_real_; ct <- table(factor(character(), levels = c("Adult","Both","Not age-specific","Pediatric")),
                                                   factor(character(), levels = c("Adult","Both","Not age-specific","Pediatric")))
  }
  AG <- data.frame(n = nrow(A_use), Agreement = po, Kappa = kappa)
  DIS <- X[X$pp != (X$rev %in% c("Yes", "Partly")),
           intersect(c("Review ID", "FULL_PROJECT_NUM", "FY", "stratum", "tier", "t2_route", "title", "rev", "Comments", "USD"), names(X)),
           drop = FALSE]
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Summary"); openxlsx::writeData(wb, "Summary", S)
  openxlsx::addWorksheet(wb, "By_stratum"); openxlsx::writeData(wb, "By_stratum", BY, rowNames = TRUE)
  openxlsx::addWorksheet(wb, "Age"); openxlsx::writeData(wb, "Age", AG)
  openxlsx::addWorksheet(wb, "Age_confusion"); openxlsx::writeData(wb, "Age_confusion", as.data.frame.matrix(ct), rowNames = TRUE)
  openxlsx::addWorksheet(wb, "Disagreements"); openxlsx::writeData(wb, "Disagreements", DIS)
  openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
  invisible(list(S = S, BY = BY, AG = AG, DIS = DIS, X = X, X0 = X0, K = K, path = out_path, idx = idx))
}

# V3 extras (18)
chd_v3_extras <- function(K, R, D, X, out_path,
                          idx_all = "data/bootstrap/boot_v3_all.idx.xz",
                          idx_nov7 = "data/bootstrap/boot_v3_noV7.idx.xz",
                          cc = "CHD focus (Yes / Partly / No / Unsure)") {
  Xw <- X
  Xw$pp <- Xw$tier != "Not CHD"
  frames <- list(
    `all 7 strata (portfolio)` = Xw,
    `without V7 no-signal stratum (CHD-signal frame)` = Xw[!startsWith(as.character(Xw$stratum), "V7"), ]
  )
  idx_map <- list(`all 7 strata (portfolio)` = idx_all,
                  `without V7 no-signal stratum (CHD-signal frame)` = idx_nov7)
  rows <- list(); k <- 1L
  for (fn in names(frames)) {
    d <- frames[[fn]]
    idx <- if (file.exists(idx_map[[fn]])) read_boot_idx(idx_map[[fn]]) else NULL
    for (tn in c("Yes|Partly", "Yes only")) {
      rp <- if (tn == "Yes|Partly") d$rev %in% c("Yes", "Partly") else d$rev == "Yes"
      m <- chd_metr(d$pp, rp, d$weight)
      q <- chd_boot_quantiles(d$pp, rp, as.numeric(d$weight), as.character(d$stratum),
                              idx = idx, idx_path = if (is.null(idx)) idx_map[[fn]] else NULL)
      if (is.null(idx)) idx <- q$idx
      for (met in c("Sensitivity", "Specificity", "PPV", "NPV", "Kappa")) {
        rows[[k]] <- data.frame(Frame = fn, `Reviewer CHD =` = tn, Metric = met,
                                `Weighted estimate` = m[[met]],
                                CI_low = unname(q$lo[met]), CI_high = unname(q$hi[met]),
                                check.names = FALSE, stringsAsFactors = FALSE)
        k <- k + 1L
      }
    }
  }
  WS <- do.call(rbind, rows)
  # prior labels
  key <- chd_read_xlsx("outputs/chd_manual_check_ANSWER_KEY.xlsx", "Key_CHD")
  r1 <- chd_read_xlsx("outputs/reviewer_returned.xlsx", "CHD_review")
  rc <- chd_read_xlsx("outputs/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx", "Map_CHD")
  rb <- chd_read_xlsx("data/validation/priority_recheck_returned.xlsx", "CHD_review")
  rc <- merge(rc, rb[, c("Review ID", cc)], by.x = "Priority_ID", by.y = "Review ID", all.x = TRUE, suffixes = c("", "_r2"), sort = FALSE)
  o <- rc[rc$Internal_Tier %in% c(1, 2) & rc[[cc]] != "Unsure", ]
  mo <- o[[cc]]; names(mo) <- as.character(o$Round1_Review_ID)
  S <- merge(key[, c("Review ID", "Project number")], r1[, c("Review ID", cc)], by = "Review ID", sort = FALSE)
  S$prior <- chd_cap1(ifelse(as.character(S$`Review ID`) %in% names(mo),
                             unname(mo[as.character(S$`Review ID`)]), S[[cc]]))
  f2c <- D$CORE_PROJECT_NUM; names(f2c) <- D$FULL_PROJECT_NUM
  S$core <- ifelse(as.character(S$`Project number`) %in% names(f2c),
                   unname(f2c[as.character(S$`Project number`)]), as.character(S$`Project number`))
  S$src <- "v1 review (adjudicated)"
  v2k <- chd_read_xlsx("outputs/v2/chd_v2_review_ANSWER_KEY.xlsx", "Key")
  v2r <- chd_read_xlsx("data/validation/v2_review_returned.xlsx", "CHD_review")
  V <- merge(v2k[, c("Review ID", "CORE_PROJECT_NUM")], v2r[, c("Review ID", cc)], by = "Review ID", sort = FALSE)
  names(V)[names(V) == "CORE_PROJECT_NUM"] <- "core"
  names(V)[names(V) == cc] <- "prior"
  V$src <- "v2 fresh set"
  P <- rbind(S[, c("core", "prior", "src")], V[, c("core", "prior", "src")])
  P <- P[!duplicated(P$core), ]
  A <- merge(K, R[, intersect(c("Review ID", cc), names(R)), drop = FALSE], by = "Review ID", sort = FALSE)
  A <- merge(A, P, by.x = "CORE_PROJECT_NUM", by.y = "core", sort = FALSE)
  A$now <- chd_cap1(A[[cc]])
  A$pos_now <- A$now %in% c("Yes", "Partly")
  A$pos_prior <- A$prior %in% c("Yes", "Partly")
  kap <- function(a, b) {
    a <- as.logical(a); b <- as.logical(b)
    po <- mean(a == b)
    pe <- mean(a) * mean(b) + (1 - mean(a)) * (1 - mean(b))
    c(po, if (pe < 1) (po - pe) / (1 - pe) else NA_real_)
  }
  srcs <- c("all", unique(as.character(A$src)))
  AG <- do.call(rbind, lapply(srcs, function(src) {
    g <- if (src == "all") A else A[A$src == src, ]
    g2 <- g[g$now != "Unsure", ]
    kk <- kap(g2$pos_now, g2$pos_prior)
    data.frame(`Earlier review` = src, `n matched` = nrow(g), `n (excl Unsure)` = nrow(g2),
               `Exact 3-level agreement` = mean(g2$now == g2$prior),
               `Binary agreement (Yes|Partly vs No)` = kk[1], `Binary kappa` = kk[2],
               check.names = FALSE, stringsAsFactors = FALSE)
  }))
  CT <- as.data.frame.matrix(table(paste(A$src, A$prior, sep = " | "), A$now))
  cm <- as.character(R$Comments); cm[is.na(cm)] <- ""
  reviewer_cols <- names(R)[grepl("^reviewer", names(R), ignore.case = TRUE) &
                              !grepl("comment|date", names(R), ignore.case = TRUE)]
  n_rev <- if (length(reviewer_cols)) length(unique(R[[reviewer_cols[1]]])) else 0
  dates <- if ("Review date (YYYY-MM-DD)" %in% names(R)) paste(unique(as.character(R$`Review date (YYYY-MM-DD)`)), collapse = ",") else ""
  INT <- data.frame(Check = c("rows", "IDs match key", "blank CHD / age", "Unsure",
                              "n distinct reviewer codes", "dates", "comments non-blank",
                              "comment length mean/sd/min/max", "comments starting ': '"),
                    Value = c(as.character(nrow(R)),
                              as.character(setequal(as.character(R$`Review ID`), as.character(K$`Review ID`))),
                              as.character(sum(is.na(R[[cc]]))),
                              as.character(sum(R[[cc]] == "Unsure", na.rm = TRUE)),
                              as.character(n_rev), dates,
                              as.character(sum(cm != "")),
                              sprintf("%.0f/%.0f/%.0f/%.0f", mean(nchar(cm)), stats::sd(nchar(cm)), min(nchar(cm)), max(nchar(cm))),
                              as.character(sum(grepl("^\\s*:\\s", cm, perl = TRUE)))),
                    stringsAsFactors = FALSE)
  chg <- A[A$pos_now != A$pos_prior, intersect(c("Review ID", "FULL_PROJECT_NUM", "stratum", "tier", "src", "prior", "now", "title"), names(A)), drop = FALSE]
  wb <- openxlsx::loadWorkbook(out_path)
  for (pair in list(list("Integrity", INT), list("Weighted_with_without_V7", WS),
                    list("Prior_label_agreement", AG), list("Prior_label_changes", chg))) {
    nm <- pair[[1]]; df <- pair[[2]]
    if (nm %in% openxlsx::sheets(wb)) openxlsx::removeWorksheet(wb, nm)
    openxlsx::addWorksheet(wb, nm); openxlsx::writeData(wb, nm, df)
  }
  if ("Prior_label_crosstab" %in% openxlsx::sheets(wb)) openxlsx::removeWorksheet(wb, "Prior_label_crosstab")
  openxlsx::addWorksheet(wb, "Prior_label_crosstab")
  openxlsx::writeData(wb, "Prior_label_crosstab", CT, rowNames = TRUE)
  openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
  invisible(list(WS = WS, AG = AG, INT = INT))
}

# Combined estimate (16)
chd_combined_estimate <- function(D, out_path, idx_path = "data/bootstrap/boot_combined.idx.xz",
                                  cc = "CHD focus (Yes / Partly / No / Unsure)") {
  key <- chd_read_xlsx("outputs/chd_manual_check_ANSWER_KEY.xlsx", "Key_CHD")
  r1 <- chd_read_xlsx("outputs/reviewer_returned.xlsx", "CHD_review")
  rc <- chd_read_xlsx("outputs/chd_manual_recheck_PRIORITY_ANSWER_KEY.xlsx", "Map_CHD")
  rb <- chd_read_xlsx("data/validation/priority_recheck_returned.xlsx", "CHD_review")
  rc <- merge(rc, rb[, c("Review ID", cc)], by.x = "Priority_ID", by.y = "Review ID", all.x = TRUE, suffixes = c("", "_r2"), sort = FALSE)
  o <- rc[rc$Internal_Tier %in% c(1, 2) & rc[[cc]] != "Unsure", ]
  mo <- o[[cc]]; names(mo) <- as.character(o$Round1_Review_ID)
  S <- merge(key[, c("Review ID", "Project number", "Fiscal year")], r1[, c("Review ID", cc)], by = "Review ID", sort = FALSE)
  S$rev <- chd_cap1(ifelse(as.character(S$`Review ID`) %in% names(mo),
                           unname(mo[as.character(S$`Review ID`)]), S[[cc]]))
  S$rev <- chd_apply_v1_overrides(S$`Review ID`, S$rev)
  S <- merge(S, D[, c("FY", "FULL_PROJECT_NUM", "tier")],
             by.x = c("Fiscal year", "Project number"), by.y = c("FY", "FULL_PROJECT_NUM"),
             all.x = TRUE, sort = FALSE)
  S <- S[match(as.character(key$`Review ID`), as.character(S$`Review ID`)), ]
  A <- S[S$tier == "Tier 1 CHD-focused", ]
  A$pp <- TRUE; A$w <- 1; A$st <- "A tier-1 census (v1 review)"
  K <- chd_read_xlsx("outputs/v2/chd_v2_review_ANSWER_KEY.xlsx", "Key")
  K <- chd_relabel_key(K, D, cols = "tier")
  R <- chd_read_xlsx("data/validation/v2_review_returned.xlsx", "CHD_review")
  B <- merge(K, R[, c("Review ID", cc)], by = "Review ID", sort = FALSE)
  B <- B[match(as.character(K$`Review ID`), as.character(B$`Review ID`)), ]
  B$rev <- chd_cap1(B[[cc]])
  B$pp <- B$tier != "Not CHD"; B$w <- as.numeric(B$weight); B$st <- as.character(B$stratum)
  X <- rbind(A[, c("pp", "rev", "w", "st")], B[, c("pp", "rev", "w", "st")])
  X <- X[X$rev %in% c("Yes", "Partly", "No"), ]
  idx <- if (file.exists(idx_path)) read_boot_idx(idx_path) else NULL
  rows <- list(); k <- 1L
  for (tn in c("Yes|Partly", "Yes only")) {
    rp <- if (tn == "Yes|Partly") X$rev %in% c("Yes", "Partly") else X$rev == "Yes"
    m <- chd_metr(X$pp, rp, X$w)
    q <- chd_boot_quantiles(X$pp, rp, X$w, X$st, idx = idx, idx_path = if (is.null(idx)) idx_path else NULL)
    if (is.null(idx)) idx <- q$idx
    for (met in c("Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa")) {
      rows[[k]] <- data.frame(`Reviewer CHD =` = tn, Metric = met, Estimate = m[[met]],
                              CI_low = unname(q$lo[met]), CI_high = unname(q$hi[met]),
                              check.names = FALSE, stringsAsFactors = FALSE)
      k <- k + 1L
    }
    rows[[k]] <- data.frame(`Reviewer CHD =` = tn, Metric = "TP/FP/FN/TN (weighted)",
                            Estimate = paste(sprintf("%.1f", c(m$TP, m$FP, m$FN, m$TN)), collapse = "/"),
                            CI_low = NA_real_, CI_high = NA_real_,
                            check.names = FALSE, stringsAsFactors = FALSE)
    k <- k + 1L
  }
  CE <- do.call(rbind, rows)
  note <- data.frame(`Combined estimate (v2 combined definition)` = c(
    sprintf("Part A: %d tier-1 core project-years from the v1 833-grant review (census of tier-1 cores; weight 1).", nrow(A)),
    sprintf("Part B: %d fresh v2 grants weighted to their strata (frame excludes all 957 previously sampled cores).", nrow(B)),
    "Excluded from both: non-tier-1 cores already reviewed in v1 (RCDC-only / near-miss samples) -> the estimate covers the CHD-signal frame minus those cores.",
    "Different reviewers in A and B; CI = stratified bootstrap (2,000) with A as one stratum. Grants with no CHD signal at all are outside the frame."
  ), check.names = FALSE, stringsAsFactors = FALSE)
  wb <- if (file.exists(out_path)) openxlsx::loadWorkbook(out_path) else openxlsx::createWorkbook()
  for (nm in c("Combined_notes", "Combined_estimate")) {
    if (nm %in% openxlsx::sheets(wb)) openxlsx::removeWorksheet(wb, nm)
  }
  openxlsx::addWorksheet(wb, "Combined_notes"); openxlsx::writeData(wb, "Combined_notes", note)
  openxlsx::addWorksheet(wb, "Combined_estimate"); openxlsx::writeData(wb, "Combined_estimate", CE)
  openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
  invisible(list(CE = CE, note = note, nA = nrow(A), nB = nrow(B), nX = nrow(X)))
}

# V4 scorer (20) -- summary metrics + disagreements; notes/reasons preserved from the Python scorer.
chd_score_v4 <- function(D, out_path, idx_all = "data/bootstrap/boot_v4_all.idx.xz",
                         idx_noA4 = "data/bootstrap/boot_v4_noA4.idx.xz") {
  cc <- "CHD focus (Yes / Partly / No / Unsure)"
  ca <- "Age population (Pediatric / Adult / Both / Neither / Unclear)"
  RET <- Sys.getenv("CHD_V4_RETURNED", "data/validation/v4_review_adjudicated.csv")
  R <- tryCatch(utils::read.csv(RET, stringsAsFactors = FALSE, check.names = FALSE, encoding = "UTF-8"),
                error = function(e) utils::read.csv(RET, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "latin1"))
  R <- R[!is.na(R$`Review ID`) & nzchar(as.character(R$`Review ID`)), ]
  R$`Review ID` <- trimws(as.character(R$`Review ID`))
  KEYP <- Sys.getenv("CHD_KEY", "outputs/v2.3/chd_v4_review_ANSWER_KEY.xlsx")
  K <- chd_relabel_key(chd_read_xlsx(KEYP, "Key"), D, cols = c("tier", "t2_route", "age_v2", "t1_drop"))
  keep <- intersect(c("Review ID", "Project number", cc, ca, "Comments", "Reviewer code", "Review date (YYYY-MM-DD)"), names(R))
  DD <- merge(K, R[, keep, drop = FALSE], by = "Review ID", all.x = TRUE, sort = FALSE)
  DD <- DD[match(as.character(K$`Review ID`), as.character(DD$`Review ID`)), ]
  DD$rev <- chd_cap1(DD[[cc]])
  DD$age_raw <- trimws(as.character(DD[[ca]]))
  DD$age <- DD$age_raw
  DD$age[DD$age == "neither"] <- "Neither"
  DD$age[DD$age == "pediatric"] <- "Pediatric"
  DD$comments <- as.character(DD$Comments); DD$comments[is.na(DD$comments)] <- ""
  X <- DD[DD$rev %in% c("Yes", "Partly", "No"), ]
  X$pp <- X$tier != "Not CHD"
  frames <- list(
    `all strata (portfolio)` = X,
    `without A4 rest-of-portfolio stratum` = X[!startsWith(as.character(X$stratum), "A4"), ]
  )
  idxf <- list(`all strata (portfolio)` = idx_all,
               `without A4 rest-of-portfolio stratum` = idx_noA4)
  rows <- list(); k <- 1L
  for (tn in c("Yes|Partly", "Yes only")) {
    for (fn in names(frames)) {
      d <- frames[[fn]]
      rp <- if (tn == "Yes|Partly") d$rev %in% c("Yes", "Partly") else d$rev == "Yes"
      for (wn in c("unweighted", "weighted")) {
        if (wn == "unweighted" && startsWith(fn, "without")) next
        w <- if (wn == "unweighted") rep(1, nrow(d)) else as.numeric(d$weight)
        m <- chd_metr(d$pp, rp, w)
        idx <- if (file.exists(idxf[[fn]])) read_boot_idx(idxf[[fn]]) else NULL
        q <- chd_boot_quantiles(d$pp, rp, w, as.character(d$stratum), idx = idx,
                                idx_path = if (is.null(idx)) idxf[[fn]] else NULL)
        den <- c(Sensitivity = m$TP + m$FN, Specificity = m$TN + m$FP,
                 PPV = m$TP + m$FP, NPV = m$TN + m$FN, Accuracy = sum(w))
        for (met in c("Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa")) {
          if (wn == "unweighted" && met != "Kappa") {
            if (met == "Accuracy") lohi <- chd_wilson(m$TP + m$TN, nrow(d))
            else lohi <- if (den[[met]]) chd_wilson(m[[met]] * den[[met]], den[[met]]) else c(NA_real_, NA_real_)
          } else lohi <- c(unname(q$lo[met]), unname(q$hi[met]))
          rows[[k]] <- data.frame(`Reviewer CHD =` = tn, Frame = fn, Weighting = wn, Metric = met,
                                  Estimate = m[[met]], CI_low = lohi[1], CI_high = lohi[2],
                                  check.names = FALSE, stringsAsFactors = FALSE)
          k <- k + 1L
        }
        rows[[k]] <- data.frame(`Reviewer CHD =` = tn, Frame = fn, Weighting = wn, Metric = "TP/FP/FN/TN",
                                Estimate = paste(sprintf("%.1f", c(m$TP, m$FP, m$FN, m$TN)), collapse = "/"),
                                CI_low = NA_real_, CI_high = NA_real_,
                                check.names = FALSE, stringsAsFactors = FALSE)
        k <- k + 1L
        if (wn == "unweighted") {
          rows[[k]] <- data.frame(`Reviewer CHD =` = tn, Frame = fn, Weighting = wn,
                                  Metric = "n answered (Unsure excluded)", Estimate = as.character(nrow(d)),
                                  CI_low = NA_real_, CI_high = NA_real_,
                                  check.names = FALSE, stringsAsFactors = FALSE)
          k <- k + 1L
        }
      }
    }
  }
  S <- do.call(rbind, rows)
  # By_stratum (Yes|Partly unweighted)
  STR_ORDER <- c(
    "A1 Clear Tier 1: CHD lesion term in title, tier 1 and RCDC CHD",
    "A2 Clear non-CHD cardiovascular (no CHD signal, CV title)",
    "A3 Clear non-CHD pediatric (no CHD signal, pediatric title)",
    "A4 Clear non-CHD: rest of NIH portfolio",
    "B1 Borderline: other Tier 1",
    "B2 Borderline: Tier 2",
    "B3 Borderline: non-CHD with CHD signal (RCDC-only, 1+ strong terms, developmental/excluded-condition title)"
  )
  BY <- do.call(rbind, lapply(STR_ORDER, function(s) {
    g <- DD[DD$stratum == s, ]
    a <- g[g$rev %in% c("Yes", "Partly", "No"), ]
    pp <- a$tier != "Not CHD"; rp <- a$rev %in% c("Yes", "Partly")
    m <- if (nrow(a)) chd_metr(pp, rp, rep(1, nrow(a))) else list()
    data.frame(stratum = s,
               N_frame = if (nrow(g)) as.integer(g$N_frame[1]) else NA_integer_,
               n_sample = if (nrow(g)) as.integer(g$n_sample[1]) else NA_integer_,
               n_answered = nrow(a), n_Unsure = sum(g$rev == "Unsure"),
               weight = if (nrow(g)) as.numeric(g$weight[1]) else NA_real_,
               rev_Yes = sum(g$rev == "Yes"), rev_Partly = sum(g$rev == "Partly"),
               rev_No = sum(g$rev == "No"), rev_Unsure = sum(g$rev == "Unsure"),
               pipeline_CHD = sum(g$tier != "Not CHD"),
               TP = sum(pp & rp), FP = sum(pp & !rp), FN = sum(!pp & rp), TN = sum(!pp & !rp),
               Sensitivity = if (length(m)) m$Sensitivity else NA_real_,
               Specificity = if (length(m)) m$Specificity else NA_real_,
               PPV = if (length(m)) m$PPV else NA_real_,
               NPV = if (length(m)) m$NPV else NA_real_,
               Kappa = if (length(m)) m$Kappa else NA_real_,
               stringsAsFactors = FALSE)
  }))
  DIS <- X[X$pp != (X$rev %in% c("Yes", "Partly")),
           intersect(c("Review ID", "FULL_PROJECT_NUM", "FY", "stratum", "tier", "t2_route", "rcdc",
                       "title", "rev", "comments", "previously_reviewed", "prior_IDs", "prior_reviews", "USD"), names(X))]
  DIS$error_type <- ifelse(DIS$tier != "Not CHD", "FP (pipeline CHD, reviewer No)",
                           "FN (pipeline not CHD, reviewer Yes|Partly)")
  # Reason text is in the shipped Python workbook; keep the same four IDs' notes when present.
  # The R pipeline fills reasons only for the known V4 disagreements; see R/20_v4_score.py.
  NOTES <- data.frame(Notes = c(
    "v2.4 pipeline vs adjudicated V4 review (200 grants). Seed for bootstrap = 1, 2,000 stratified draws.",
    "Primary truth: reviewer Yes or Partly = CHD. Yes-only is a sensitivity check. Two Unsure rows (both B2) are excluded from all metrics; original stratum weights are kept, so B2 contributes 8/10 of its frame weight.",
    "Unweighted figures describe this clear-case-heavy sample and will look better than portfolio performance. Use weighted figures for portfolio inference.",
    "A4 (rest of NIH portfolio) has weight 43,833.4 and 5 true negatives; it dominates weighted specificity, accuracy, NPV and kappa. Report weighted results both with and without A4.",
    "Standing rules (unchanged): exclude pediatric/neonatal pulmonary hypertension, congenital heart block and noncompaction unless another CHD lesion is also named; keep coarctation, PDA and SVAS; keep the F30/F31 anchor.",
    "See the Disagreements sheet. Scoring command: Rscript R/run_v2.4_all.R",
    "Returned file copied to data/validation/v4_review_adjudicated.csv (Windows/Latin-1 encoding; two trailing empty rows dropped)."
  ), stringsAsFactors = FALSE)

  # V4 age agreement (secondary; among grants both sides call CHD)
  A <- X[X$pp & X$rev %in% c("Yes", "Partly"), , drop = FALSE]
  A$rev_age <- as.character(A$age)
  A$rev_age[A$rev_age == "Neither"] <- "Not age-specific"
  A_use <- A[A$rev_age %in% c("Pediatric", "Adult", "Both", "Not age-specific"), , drop = FALSE]
  if (nrow(A_use)) {
    po_a <- mean(A_use$rev_age == A_use$age_v2)
    lv <- c("Adult", "Both", "Not age-specific", "Pediatric")
    ct_age <- table(factor(A_use$rev_age, levels = lv), factor(A_use$age_v2, levels = lv))
    pe_a <- sum(rowSums(ct_age) * colSums(ct_age)) / nrow(A_use)^2
    kappa_a <- if (pe_a < 1) (po_a - pe_a) / (1 - pe_a) else NA_real_
  } else {
    po_a <- NA_real_; kappa_a <- NA_real_
    lv <- c("Adult", "Both", "Not age-specific", "Pediatric")
    ct_age <- table(factor(character(), levels = lv), factor(character(), levels = lv))
  }
  AG <- data.frame(`n both-sides CHD` = nrow(A),
                   `n age capitalization normalized` = sum(A$age != A$age_raw, na.rm = TRUE),
                   `n age 'Both (unclear)' excluded from kappa` = sum(A$age == "Both (unclear)", na.rm = TRUE),
                   `n used for agreement` = nrow(A_use),
                   Agreement = po_a, Kappa = kappa_a,
                   check.names = FALSE, stringsAsFactors = FALSE)

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Notes"); openxlsx::writeData(wb, "Notes", NOTES)
  openxlsx::addWorksheet(wb, "Summary"); openxlsx::writeData(wb, "Summary", S)
  openxlsx::addWorksheet(wb, "By_stratum"); openxlsx::writeData(wb, "By_stratum", BY)
  openxlsx::addWorksheet(wb, "Disagreements"); openxlsx::writeData(wb, "Disagreements", DIS)
  openxlsx::addWorksheet(wb, "Age"); openxlsx::writeData(wb, "Age", AG)
  openxlsx::addWorksheet(wb, "Age_confusion"); openxlsx::writeData(wb, "Age_confusion", as.data.frame.matrix(ct_age), rowNames = TRUE)
  openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
  invisible(list(S = S, BY = BY, DIS = DIS, AG = AG, path = out_path, nX = nrow(X)))
}

# v2.4 vs v2.3 label-change workbook
chd_label_changes <- function(pool, D24, out_path) {
  D23 <- chd_classify(pool, version = "2.3")
  # FY totals
  years <- 2013:2026
  fy_tab <- function(Dx, suffix) {
    kw1 <- if ("kw_v1" %in% names(Dx)) Dx$kw_v1 else Dx$kw
    sumM <- function(mask) {
      v <- tapply(Dx$USD[mask], factor(Dx$FY[mask], levels = years), sum, default = 0)
      v[is.na(v)] <- 0; as.numeric(v) / 1e6
    }
    nY <- function(mask) as.integer(table(factor(Dx$FY[mask], levels = years)))
    rcdc <- Dx$rcdc & Dx$FY >= 2016 & Dx$FY <= 2025
    Y <- data.frame(FY = years,
                    old_keyword_M = sumM(kw1), tier1_M = sumM(Dx$tier1), tier2_M = sumM(Dx$tier2),
                    combined_M = sumM(Dx$chd_v2), RCDC_M = sumM(rcdc),
                    tier1_n = nY(Dx$tier1), tier2_n = nY(Dx$tier2), combined_n = nY(Dx$chd_v2),
                    old_n = nY(kw1), stringsAsFactors = FALSE)
    Y$combined_vs_old_pct <- 100 * (Y$combined_M / Y$old_keyword_M - 1)
    Y$combined_pct_of_RCDC <- 100 * Y$combined_M / Y$RCDC_M
    Y$RCDC_M[!(Y$FY %in% 2016:2025)] <- NA_real_
    Y$combined_pct_of_RCDC[!(Y$FY %in% 2016:2025)] <- NA_real_
    names(Y)[-1] <- paste0(names(Y)[-1], suffix)
    Y
  }
  Y <- merge(fy_tab(D23, "_v2.3"), fy_tab(D24, "_v2.4"), by = "FY", sort = FALSE)
  for (pref in c("tier1_M", "tier2_M", "combined_M", "tier1_n", "tier2_n", "combined_n")) {
    Y[[paste0(pref, "_delta")]] <- Y[[paste0(pref, "_v2.4")]] - Y[[paste0(pref, "_v2.3")]]
  }
  # round display like the shipped sheet (2 decimals on $ and percents)
  Yw <- Y
  num <- names(Yw)[sapply(Yw, is.numeric) & names(Yw) != "FY"]
  intc <- grep("_n|_delta$", num, value = TRUE)
  intc <- intc[grepl("_n", intc)]
  for (cn in setdiff(num, grep("_n", num, value = TRUE))) Yw[[cn]] <- chd_round(Yw[[cn]], 2)
  chg <- D23[, c("FY", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "USD", "title", "tier", "t2_route", "chd_v2")]
  names(chg)[names(chg) == "tier"] <- "tier_23"
  names(chg)[names(chg) == "t2_route"] <- "t2_route_23"
  names(chg)[names(chg) == "chd_v2"] <- "combined_23"
  chg <- merge(chg, D24[, c("FY", "FULL_PROJECT_NUM", "tier", "t2_route", "t1_drop", "chd_v2")],
               by = c("FY", "FULL_PROJECT_NUM"), sort = FALSE)
  names(chg)[names(chg) == "tier"] <- "tier_24"
  names(chg)[names(chg) == "t2_route"] <- "t2_route_24"
  names(chg)[names(chg) == "chd_v2"] <- "combined_24"
  chg <- chg[chg$tier_23 != chg$tier_24, ]
  chg$direction <- paste(chg$tier_23, chg$tier_24, sep = " -> ")
  chg$title <- chd_deidentify_title(chg$title)
  # dropouts by FY
  drops <- do.call(rbind, lapply(years, function(y) {
    g <- chg[chg$FY == y & chg$combined_23 & !chg$combined_24, ]
    data.frame(FY = y, n_dropped = nrow(g),
               USD_M_dropped = chd_round(sum(g$USD) / 1e6, 2),
               cores = if (nrow(g)) paste(unique(g$CORE_PROJECT_NUM), collapse = "; ") else "0",
               stringsAsFactors = FALSE)
  }))
  Notes <- data.frame(Notes = c(
    "v2.4 vs v2.3 pipeline labels. Reference labels were not changed.",
    "Laterality rule: Tier 2 left-right/laterality terms count only when the grant also has a cardiac/CHD link (heart, cardiac, a kept lesion, cardiac/heart/c-looping). Bare heterotaxy is not enough. Example dropped: V4-129 / V2-148, stomach curvature.",
    "Study-aim gate (Tier 1): a keyword-positive grant without CHD/lesion in the title is demoted only if CHD terms appear solely as an associated phenotype of a gene/protein under study (after those tails are stripped: no CHD in aims and fewer than two substantive CHD sentences). Safety nets keep grants that name a kept lesion (PDA, SVAS, coarctation) in the title or text, and grants with substantial cardiogenesis vocabulary plus a CHD/lesion mention. Example dropped: V4-188 / B-CHD-751.",
    "Portfolio impact is two cores (5 project-years). No new false negatives in the review sets; both dropped review-set grants were already reviewer No (corrected false positives)."
  ), stringsAsFactors = FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Notes"); openxlsx::writeData(wb, "Notes", Notes)
  openxlsx::addWorksheet(wb, "FY_totals_vs_v2.3"); openxlsx::writeData(wb, "FY_totals_vs_v2.3", Yw)
  openxlsx::addWorksheet(wb, "FY_combined_dropouts"); openxlsx::writeData(wb, "FY_combined_dropouts", drops)
  openxlsx::addWorksheet(wb, "Portfolio_project_year_changes")
  openxlsx::writeData(wb, "Portfolio_project_year_changes",
                      chg[, c("FY", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "USD", "title",
                              "tier_23", "t2_route_23", "tier_24", "t2_route_24", "t1_drop",
                              "direction", "combined_23", "combined_24")])
  openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
  invisible(list(Y = Y, chg = chg, path = out_path))
}

run_v24_scoring <- function(D, pool = NULL, out_dir = NULL) {
  if (is.null(out_dir)) out_dir <- Sys.getenv("CHD_V2_OUT", "outputs/v2.4")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  if (!requireNamespace("readxl", quietly = TRUE) || !requireNamespace("openxlsx", quietly = TRUE))
    stop("Packages readxl and openxlsx are required")
  # v2 set + combined
  v2_out <- file.path(out_dir, "chd_v2.4_score_v2set.xlsx")
  k2 <- chd_read_xlsx("outputs/v2/chd_v2_review_ANSWER_KEY.xlsx", "Key")
  r2 <- chd_read_xlsx("data/validation/v2_review_returned.xlsx", "CHD_review")
  s2 <- chd_score_review(k2, r2, D, v2_out, "data/bootstrap/boot_v2set.idx.xz")
  comb <- chd_combined_estimate(D, v2_out, "data/bootstrap/boot_combined.idx.xz")
  # V3
  v3_out <- file.path(out_dir, "chd_v3_review_scoring_v2.4.xlsx")
  k3 <- chd_read_xlsx("outputs/v2.1/chd_v3_review_ANSWER_KEY.xlsx", "Key")
  r3 <- chd_read_xlsx(Sys.getenv("CHD_V3_RETURNED", "data/validation/v3_review_returned_v2.3ref.xlsx"), "CHD_review")
  s3 <- chd_score_review(k3, r3, D, v3_out, "data/bootstrap/boot_v3_all.idx.xz")
  ex3 <- chd_v3_extras(s3$K, r3, D, s3$X, v3_out)
  # V4
  v4_out <- file.path(out_dir, "chd_v4_review_scoring_v2.4.xlsx")
  s4 <- chd_score_v4(D, v4_out)
  # label changes
  if (is.null(pool)) pool <- load_v2_pool()
  lc <- chd_label_changes(pool, D, file.path(out_dir, "chd_v2.4_label_changes.xlsx"))
  invisible(list(v2 = s2, comb = comb, v3 = s3, v3ex = ex3, v4 = s4, labels = lc))
}

if (identical(environment(), globalenv()) && !interactive() &&
    any(grepl("25_v24_score\\.R$", commandArgs(trailingOnly = FALSE)))) {
  setwd(chd_root())
  source("R/23_v24_classify.R")
  D <- chd_classify(load_v2_pool(), version = "2.4")
  run_v24_scoring(D)
}
