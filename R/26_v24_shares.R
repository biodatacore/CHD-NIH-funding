# 26_v24_shares.R -- R port of R/21_v24_shares.py
# Yearly shares, age, overlap, mortality, APC/CAGR, v1 self-check, key numbers.

if (!exists("chd_root")) source("R/chd_v24_metrics.R")
if (!exists("chd_as_logical")) source("R/23_v24_classify.R")

TREND_YEARS <- 2013:2025
MORT_YEARS <- 2013:2024
TIER_COMBINED <- c("Tier 1 CHD-focused", "Tier 2 CHD-related basic/developmental")
AGE_LEVELS_V24 <- c("Pediatric", "Adult", "Both", "Not age-specific")

chd_r4 <- function(x) {
  if (length(x) != 1L || is.null(x) || is.na(x)) return(x)
  round(as.numeric(x), 4)
}

log_linear_trend <- function(years, values, label, year_set = NULL) {
  d <- data.frame(y = as.numeric(years), v = as.numeric(values))
  d <- d[is.finite(d$y) & is.finite(d$v), , drop = FALSE]
  if (!is.null(year_set)) d <- d[d$y %in% year_set, , drop = FALSE]
  d <- d[d$v > 0, , drop = FALSE]
  d <- d[order(d$y), , drop = FALSE]
  if (nrow(d) < 3L) stop("not enough points for trend: ", label)
  fit <- stats::lm(log(v) ~ y, data = d)
  sm <- summary(fit)
  b <- unname(coef(fit)[["y"]])
  ci <- stats::confint(fit, "y", level = 0.95)
  lo <- unname(ci[1, 1]); hi <- unname(ci[1, 2])
  first <- d$v[1]; last <- d$v[nrow(d)]
  y0 <- as.integer(d$y[1]); y1 <- as.integer(d$y[nrow(d)])
  span <- y1 - y0
  yrs <- if (is.null(year_set) || (min(year_set) >= 2013 && max(year_set) <= 2026))
    sprintf("FY%d-%d", y0, y1) else sprintf("%d-%d", y0, y1)
  data.frame(series = label, years = yrs, start = first, end = last,
             CAGR_pct = 100 * ((last / first)^(1 / span) - 1),
             APC_pct = 100 * (exp(b) - 1),
             APC_lo = 100 * (exp(lo) - 1),
             APC_hi = 100 * (exp(hi) - 1),
             p = unname(sm$coefficients["y", "Pr(>|t|)"]),
             n = nrow(d), stringsAsFactors = FALSE)
}

chd_keys <- function(fy, num) paste(as.integer(fy), as.character(num), sep = "|")

load_denominators <- function() {
  d <- utils::read.csv("data/work/nih_cvd_yearly.csv", stringsAsFactors = FALSE, check.names = FALSE)
  d$FY <- as.integer(d$FY)
  d$NIH_USD_B <- d$NIH_USD / 1e9
  d$CVD_USD_B <- d$CVD_USD / 1e9
  d$rcdc_USD_M <- d$rcdc_USD / 1e6
  d
}

load_v24_projects <- function(funding_xlsx = "outputs/v2.4/chd_v2_funding.xlsx") {
  if (!requireNamespace("readxl", quietly = TRUE)) stop("readxl is required")
  proj <- as.data.frame(readxl::read_excel(funding_xlsx, sheet = "Projects"))
  proj$FY <- as.integer(proj$FY)
  proj$key <- chd_keys(proj$FY, proj$FULL_PROJECT_NUM)
  proj$combined <- proj$tier %in% TIER_COMBINED
  flags <- utils::read.csv("data/work/v24_cv_flags.csv", stringsAsFactors = FALSE)
  flags$FY <- as.integer(flags$FY)
  flags$cv <- chd_as_logical(flags$cv)
  flags$key <- chd_keys(flags$FY, flags$FULL_PROJECT_NUM)
  proj <- merge(proj, flags[, c("key", "cv")], by = "key", all.x = TRUE, sort = FALSE)
  if (any(is.na(proj$cv))) stop("v24_cv_flags.csv missing ", sum(is.na(proj$cv)), " project-years")
  proj$cv <- chd_as_logical(proj$cv)
  proj
}

attach_denom <- function(chd, denoms) {
  D <- merge(denoms, chd, by = "FY", all.x = TRUE, sort = TRUE)
  D$CVD_pct_of_NIH <- 100 * D$CVD_USD_B / D$NIH_USD_B
  D$CHD_pct_of_CVD <- 100 * D$CHD_in_CVD_USD_M / (D$CVD_USD_B * 1e3)
  D$CHDall_pct_of_CVD <- 100 * D$CHD_USD_M / (D$CVD_USD_B * 1e3)
  D$CHD_pct_of_NIH <- 100 * D$CHD_USD_M / (D$NIH_USD_B * 1e3)
  D$rcdc_pct_of_NIH <- 100 * D$rcdc_USD_M / (D$NIH_USD_B * 1e3)
  na <- !(D$FY >= 2016 & D$FY <= 2025)
  D$rcdc_projects[na] <- NA
  D$rcdc_USD_M[na] <- NA
  D$rcdc_pct_of_NIH[na] <- NA
  if ("rcdc_USD" %in% names(D)) D$rcdc_USD[na] <- NA
  D[order(D$FY), ]
}

yearly_v1 <- function(denoms) {
  k <- utils::read.csv("data/work/v1_keyword_yearly.csv", stringsAsFactors = FALSE)
  k$FY <- as.integer(k$FY)
  chd <- data.frame(FY = k$FY, CHD_projects = k$CHD_projects, CHD_USD_M = k$CHD_USD / 1e6,
                    CHD_in_CVD_projects = k$CHD_in_CVD_projects, CHD_in_CVD_USD_M = k$CHD_in_CVD_USD / 1e6,
                    CHD_not_CVD_USD_M = k$CHD_not_CVD_USD / 1e6)
  attach_denom(chd, denoms)
}

yearly_v24 <- function(denoms, proj) {
  c <- proj[proj$combined, , drop = FALSE]
  rows <- do.call(rbind, lapply(split(c, c$FY), function(g) {
    data.frame(FY = as.integer(g$FY[1]), CHD_projects = nrow(g),
               CHD_USD_M = sum(g$USD) / 1e6, CHD_in_CVD_projects = sum(g$cv),
               CHD_in_CVD_USD_M = sum(g$USD[g$cv]) / 1e6,
               CHD_not_CVD_USD_M = sum(g$USD[!g$cv]) / 1e6)
  }))
  attach_denom(rows, denoms)
}

age_table <- function(df, age_col, fy_col = "FY", usd_col = "USD") {
  g <- aggregate(df[[usd_col]], list(FY = df[[fy_col]], age = as.character(df[[age_col]])),
                 function(z) c(USD = sum(z), n = length(z)))
  # aggregate returns a matrix column
  USD <- if (is.matrix(g$x)) g$x[, 1] else sapply(g$x, `[`, 1)
  n <- if (is.matrix(g$x)) g$x[, 2] else sapply(g$x, `[`, 2)
  out <- data.frame(FY = as.integer(g$FY), age = g$age, USD = as.numeric(USD), n = as.integer(n))
  out$USD_M <- out$USD / 1e6
  tot <- tapply(out$USD_M, out$FY, sum)
  out$pct_of_CHD <- 100 * out$USD_M / as.numeric(tot[as.character(out$FY)])
  out[order(out$FY, out$age), ]
}

age_from_v1 <- function() {
  a <- utils::read.csv("data/work/v1_keyword_age.csv", stringsAsFactors = FALSE)
  a$FY <- as.integer(a$FY)
  age_table(a, "age")
}

age_from_v24 <- function(proj, in_cvd = FALSE) {
  c <- proj[proj$combined, , drop = FALSE]
  if (in_cvd) c <- c[c$cv, , drop = FALSE]
  age_table(c, "age_v2")
}

mortality_from_wonder <- function() {
  R <- utils::read.csv("data/wonder/wonder_long.csv", stringsAsFactors = FALSE)
  S <- R[((R$source == "bridged") & R$year %in% 2013:2017) |
           ((R$source == "single") & R$year %in% 2018:2024), ]
  # pivot measure_age
  S$key <- paste(S$measure, S$age, sep = "_")
  W <- reshape(S[, c("year", "key", "deaths")], idvar = "year", timevar = "key",
               direction = "wide")
  names(W) <- sub("^deaths\\.", "", names(W))
  W$chd_ucd_adult <- W$chd_ucd_all - W$chd_ucd_ped
  W$chd_any_adult <- W$chd_any_all - W$chd_any_ped
  W$cvd_adult <- W$cvd_all - W$cvd_ped
  W$heart_adult <- W$heart_all - W$heart_ped
  for (g in c("all", "ped", "adult")) {
    W[[paste0("cvd_", g)]] <- W[[paste0("cvd_", g)]] + W[[paste0("chd_ucd_", g)]]
    W[[paste0("heart_", g)]] <- W[[paste0("heart_", g)]] + W[[paste0("chd_ucd_", g)]]
  }
  for (g in c("all", "ped", "adult")) {
    for (m in c("chd_ucd", "chd_any")) {
      for (d in c("cvd", "heart")) {
        W[[sprintf("%s_pct_of_%s_%s", m, d, g)]] <- 100 * W[[paste0(m, "_", g)]] / W[[paste0(d, "_", g)]]
      }
    }
  }
  W$file_note <- ifelse(W$year <= 2017, "D76 (UCD) / D77 (MCD), bridged-race final",
                        "D158 (UCD) / D157 (MCD), single-race final")
  ov <- R[R$year %in% 2018:2020, c("year", "measure", "age", "source", "deaths")]
  ov <- reshape(ov, idvar = c("year", "measure", "age"), timevar = "source", direction = "wide")
  names(ov) <- sub("^deaths\\.", "", names(ov))
  if (all(c("bridged", "single") %in% names(ov))) ov$diff <- ov$single - ov$bridged
  ov <- ov[order(ov$year, ov$measure, ov$age), ]
  rownames(ov) <- NULL
  list(W = W[order(W$year), ], ov = ov, R = R)
}

overlap_vs_rcdc <- function(proj) {
  comb <- proj[proj$combined, c("FY", "FULL_PROJECT_NUM", "USD")]
  comb$key <- chd_keys(comb$FY, comb$FULL_PROJECT_NUM)
  rcdc <- utils::read.csv("data/work/rcdc_chd_projects.csv", stringsAsFactors = FALSE)
  rcdc$FY <- as.integer(rcdc$FY)
  rcdc$key <- chd_keys(rcdc$FY, rcdc$FULL_PROJECT_NUM)
  years <- sort(unique(c(rcdc$FY, comb$FY[comb$FY >= 2016 & comb$FY <= 2025])))
  rows <- lapply(years, function(fy) {
    c <- comb[comb$FY == fy, ]
    r <- rcdc[rcdc$FY == fy, ]
    both <- intersect(c$key, r$key); only_c <- setdiff(c$key, r$key); only_r <- setdiff(r$key, c$key)
    data.frame(FY = as.integer(fy), both_n = length(both), classifier_only_n = length(only_c),
               rcdc_only_n = length(only_r),
               both_M = sum(c$USD[c$key %in% both]) / 1e6,
               classifier_only_M = sum(c$USD[c$key %in% only_c]) / 1e6,
               rcdc_only_M = sum(r$USD[r$key %in% only_r]) / 1e6)
  })
  O <- do.call(rbind, rows)
  tot <- data.frame(FY = NA_integer_, both_n = sum(O$both_n), classifier_only_n = sum(O$classifier_only_n),
                    rcdc_only_n = sum(O$rcdc_only_n), both_M = sum(O$both_M),
                    classifier_only_M = sum(O$classifier_only_M), rcdc_only_M = sum(O$rcdc_only_M))
  O <- rbind(O, tot)
  O$iou_projects <- O$both_n / (O$both_n + O$classifier_only_n + O$rcdc_only_n)
  O$pct_classifier_in_rcdc <- 100 * O$both_n / (O$both_n + O$classifier_only_n)
  O$pct_rcdc_in_classifier <- 100 * O$both_n / (O$both_n + O$rcdc_only_n)
  O$iou_dollars <- O$both_M / (O$both_M + O$classifier_only_M + O$rcdc_only_M)
  O
}

period_pooled <- function(D, years, name) {
  s <- D[D$FY %in% years, ]
  data.frame(period = name,
             CHD_pct_of_CVD = 100 * sum(s$CHD_in_CVD_USD_M) / (1e3 * sum(s$CVD_USD_B)),
             CHD_pct_of_NIH = 100 * sum(s$CHD_USD_M) / (1e3 * sum(s$NIH_USD_B)),
             CVD_pct_of_NIH = 100 * sum(s$CVD_USD_B) / sum(s$NIH_USD_B),
             stringsAsFactors = FALSE)
}

funding_trends <- function(D, age_all, age_levels, chd_label) {
  rows <- list(
    log_linear_trend(D$FY, D$NIH_USD_B, "Total NIH ($B)", TREND_YEARS),
    log_linear_trend(D$FY, D$CVD_USD_B, "Total CVD ($B)", TREND_YEARS),
    log_linear_trend(D$FY, D$CVD_pct_of_NIH, "CVD % of NIH", TREND_YEARS),
    log_linear_trend(D$FY, D$CHD_in_CVD_USD_M, sprintf("CHD within CVD ($M) [%s]", chd_label), TREND_YEARS),
    log_linear_trend(D$FY, D$CHD_pct_of_CVD, sprintf("CHD %% of CVD [%s]", chd_label), TREND_YEARS),
    log_linear_trend(D$FY, D$CHD_USD_M, sprintf("CHD all ($M) [%s]", chd_label), TREND_YEARS),
    log_linear_trend(D$FY, D$CHD_pct_of_NIH, sprintf("CHD %% of NIH [%s]", chd_label), TREND_YEARS)
  )
  d <- D[D$FY %in% 2016:2025 & is.finite(D$rcdc_USD_M), ]
  rows <- c(rows, list(
    log_linear_trend(d$FY, d$rcdc_USD_M, "CHD, RCDC ($M; FY2016-2025)", 2016:2025),
    log_linear_trend(d$FY, d$rcdc_pct_of_NIH, "CHD % of NIH (RCDC; FY2016-2025)", 2016:2025)
  ))
  for (a in age_levels) {
    sub <- age_all[age_all$age == a, ]
    mm <- merge(D[, "FY", drop = FALSE], sub[, c("FY", "USD_M", "pct_of_CHD")], by = "FY", all.x = TRUE, sort = TRUE)
    mm$USD_M[is.na(mm$USD_M)] <- 0
    mm$pct_of_CHD[is.na(mm$pct_of_CHD)] <- 0
    rows <- c(rows, list(tryCatch(log_linear_trend(mm$FY, mm$USD_M, sprintf("CHD %s ($M) [%s]", a, chd_label), TREND_YEARS), error = function(e) NULL)))
    rows <- c(rows, list(tryCatch(log_linear_trend(mm$FY, mm$pct_of_CHD, sprintf("CHD %s (%% of CHD $) [%s]", a, chd_label), TREND_YEARS), error = function(e) NULL)))
  }
  do.call(rbind, Filter(Negate(is.null), rows))
}

mortality_trends <- function(W) {
  pref <- c("chd_any_all", "chd_any_ped", "chd_ucd_all", "chd_ucd_ped",
            "cvd_all", "cvd_ped", "heart_all", "heart_ped",
            "chd_ucd_adult", "chd_any_adult", "cvd_adult", "heart_adult",
            "chd_ucd_pct_of_cvd_all", "chd_ucd_pct_of_heart_all",
            "chd_any_pct_of_cvd_all", "chd_any_pct_of_heart_all",
            "chd_ucd_pct_of_cvd_ped", "chd_ucd_pct_of_heart_ped",
            "chd_any_pct_of_cvd_ped", "chd_any_pct_of_heart_ped",
            "chd_ucd_pct_of_cvd_adult", "chd_ucd_pct_of_heart_adult",
            "chd_any_pct_of_cvd_adult", "chd_any_pct_of_heart_adult",
            "CHD_pct_of_CVD_funding")
  alln <- names(W)[names(W) != "year" & names(W) != "file_note" & vapply(W, is.numeric, logical(1))]
  keep <- c(intersect(pref, alln), setdiff(alln, pref))
  rows <- lapply(keep, function(c) {
    tryCatch({
      t <- log_linear_trend(W$year, W[[c]], c, MORT_YEARS)
      t$years <- "2013-2024"
      t$y2013 <- t$start; t$y2024 <- t$end
      t$start <- NULL; t$end <- NULL
      t
    }, error = function(e) NULL)
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}

self_check_v1 <- function(D_v1, age_v1, W, trends_v1, out_path) {
  v1_ctx <- utils::read.csv("data/work/v1_expected_cvd_nih_context.csv", stringsAsFactors = FALSE)
  v1_tr <- utils::read.csv("data/work/v1_expected_cvd_trends.csv", stringsAsFactors = FALSE)
  v1_mort <- utils::read.csv("data/work/v1_expected_mortality_yearly.csv", stringsAsFactors = FALSE)
  lines <- character(); ok <- TRUE
  chk <- function(label, got, exp, atol = 5e-5) {
    g <- chd_r4(got); e <- chd_r4(exp)
    match <- isTRUE(all.equal(g, e)) || (is.finite(got) && is.finite(exp) && abs(as.numeric(got) - as.numeric(exp)) <= atol)
    if (!match) ok <<- FALSE
    lines <<- c(lines, sprintf("  [%s] %s: got %s (r4=%s)  expected %s (r4=%s)",
                               if (match) "OK" else "FAIL", label, deparse(got)[1], deparse(g)[1], deparse(exp)[1], deparse(e)[1]))
  }
  lines <- c(lines, "V1 SELF-CHECK (keyword classifier, same denominators as R/07_cvd.R and R/05_analysis.R)")
  lines <- c(lines, "v1 expected tables: data/work/v1_expected_*.csv (values taken from the v1 funding workbook)")
  m <- merge(D_v1, v1_ctx, by = "FY", suffixes = c("_got", "_exp"), sort = TRUE)
  for (i in seq_len(nrow(m))) {
    fy <- as.integer(m$FY[i])
    for (col in c("NIH_USD_B", "CVD_USD_B", "CVD_pct_of_NIH", "CHD_USD_M", "CHD_in_CVD_USD_M",
                  "CHD_pct_of_CVD", "CHDall_pct_of_CVD", "CHD_pct_of_NIH")) {
      chk(sprintf("FY%d %s", fy, col), m[[paste0(col, "_got")]][i], m[[paste0(col, "_exp")]][i])
    }
    chk(sprintf("FY%d Yearly.chd_USD_M", fy), m$CHD_USD_M_got[i], m$chd_USD_M[i])
    chk(sprintf("FY%d Yearly.chd_pct_of_NIH", fy), m$CHD_pct_of_NIH_got[i], m$chd_pct_of_NIH[i])
    chk(sprintf("FY%d Yearly.nih_projects", fy), m$nih_projects_got[i], m$nih_projects_exp[i])
  }
  d13 <- D_v1[D_v1$FY == 2013, ][1, ]; d25 <- D_v1[D_v1$FY == 2025, ][1, ]
  lines <- c(lines, "", "Headline endpoints:")
  chk("FY2013 CHD_pct_of_CVD", d13$CHD_pct_of_CVD, 2.2124)
  chk("FY2025 CHD_pct_of_CVD", d25$CHD_pct_of_CVD, 2.1654)
  chk("FY2013 CHD_pct_of_NIH", d13$CHD_pct_of_NIH, 0.2257)
  chk("FY2025 CHD_pct_of_NIH", d25$CHD_pct_of_NIH, 0.2033)
  name_map <- c("Total NIH ($B)" = "Total NIH ($B)", "Total CVD ($B)" = "Total CVD ($B)",
                "CVD % of NIH" = "CVD % of NIH",
                "CHD within CVD ($M) [v1 keyword]" = "CHD within CVD ($M)",
                "CHD % of CVD [v1 keyword]" = "CHD % of CVD",
                "CHD all ($M) [v1 keyword]" = "CHD all ($M)",
                "CHD % of NIH [v1 keyword]" = "CHD % of NIH")
  for (got_name in names(name_map)) {
    exp_name <- unname(name_map[[got_name]])
    g <- trends_v1[trends_v1$series == got_name, ]; e <- v1_tr[v1_tr$series == exp_name, ]
    if (!nrow(g) || !nrow(e)) { lines <- c(lines, sprintf("  [FAIL] missing trend %s / %s", got_name, exp_name)); ok <- FALSE; next }
    g <- g[1, ]; e <- e[1, ]
    for (pair in list(c("start", "start_FY2013"), c("end", "end_FY2025"), c("CAGR_pct", "CAGR_pct"),
                      c("APC_pct", "APC_pct"), c("APC_lo", "APC_lo"), c("APC_hi", "APC_hi"), c("p", "p"))) {
      chk(sprintf("CVD_trends %s %s", exp_name, pair[1]), g[[pair[1]]], e[[pair[2]]])
    }
  }
  wm <- merge(W, v1_mort, by = "year", suffixes = c("_got", "_exp"), sort = TRUE)
  for (col in c("chd_ucd_all", "chd_ucd_ped", "chd_ucd_adult", "chd_any_all", "chd_any_ped",
                "chd_any_adult", "cvd_all", "cvd_ped", "cvd_adult",
                "chd_ucd_pct_of_cvd_all", "chd_any_pct_of_cvd_all",
                "chd_ucd_pct_of_cvd_ped", "chd_any_pct_of_cvd_adult", "chd_ucd_pct_of_cvd_adult")) {
    for (i in seq_len(nrow(wm))) {
      chk(sprintf("mortality %d %s", as.integer(wm$year[i]), col), wm[[paste0(col, "_got")]][i], wm[[paste0(col, "_exp")]][i])
    }
  }
  for (i in seq_len(nrow(v1_mort))) {
    fy <- as.integer(v1_mort$year[i])
    exp <- D_v1$CHD_pct_of_CVD[D_v1$FY == fy]
    if (length(exp)) chk(sprintf("Mortality_yearly FY%d CHD_pct_of_CVD_funding vs expected context", fy),
                         v1_mort$CHD_pct_of_CVD_funding[i], exp[1])
  }
  lines <- c(lines, "", paste("RESULT:", if (ok) "ALL CHECKS PASSED" else "FAILURES PRESENT"))
  text <- paste(c(lines, ""), collapse = "\n")
  writeLines(text, out_path)
  list(ok = ok, text = text)
}

ic_shares <- function(proj) {
  c <- proj[proj$combined, ]
  out <- list()
  for (lab in c("FY2013-2025", "FY2013-2026")) {
    s <- if (lab == "FY2013-2025") c[c$FY %in% TREND_YEARS, ] else c[c$FY >= 2013 & c$FY <= 2026, ]
    tot <- sum(s$USD); hl <- sum(s$USD[s$IC == "HL"])
    out[[lab]] <- list(total = tot / 1e6, nhlbi = hl / 1e6, nhlbi_pct = 100 * hl / tot, n = nrow(s))
  }
  out
}

rcdc_outside <- function(O) {
  tot <- O[!is.na(O$FY), ]
  rcdc_d <- sum(tot$both_M) + sum(tot$rcdc_only_M)
  only <- sum(tot$rcdc_only_M)
  list(rcdc_only_M = only, rcdc_total_M = rcdc_d,
       pct_rcdc_dollars_outside_v24 = 100 * only / rcdc_d,
       pct_v24_dollars_inside_rcdc = 100 * sum(tot$both_M) / (sum(tot$both_M) + sum(tot$classifier_only_M)))
}

val_rows_from_scoring <- function(score_dir = "outputs/v2.4") {
  rows <- list()
  add <- function(item, value, source, sheet, note = "") {
    rows <<- c(rows, list(data.frame(section = "Validation", item = item, value = I(as.character(value)),
                                     window = "", unit = "", source_file = as.character(source),
                                     source_sheet = sheet, note = note, stringsAsFactors = FALSE)))
  }
  # keep numeric values as-is via list then bind with mixed types later
  recs <- list()
  add2 <- function(item, value, source, sheet, note = "") {
    recs <<- c(recs, list(list(section = "Validation", item = item, value = value, window = "",
                               unit = "", source_file = as.character(source), source_sheet = sheet, note = note)))
  }
  v3 <- file.path(score_dir, "chd_v3_review_scoring_v2.4.xlsx")
  v4 <- file.path(score_dir, "chd_v4_review_scoring_v2.4.xlsx")
  comb <- file.path(score_dir, "chd_v2.4_score_v2set.xlsx")
  s <- as.data.frame(readxl::read_excel(v3, "Summary"))
  w <- as.data.frame(readxl::read_excel(v3, "Weighted_with_without_V7"))
  u <- s[s$`Reviewer CHD =` == "Yes|Partly" & s$Weighting == "unweighted", ]
  for (i in seq_len(nrow(u))) {
    r <- u[i, ]
    add2(sprintf("V3 unweighted Yes|Partly %s", r$Metric), r$Estimate, v3, "Summary",
         if (!is.na(r$CI_low)) sprintf("CI %s to %s", r$CI_low, r$CI_high) else "n=197 after 3 Unsure excluded (TP/FP/FN/TN 109/6/15/67)")
    if (!is.na(r$CI_low)) {
      add2(sprintf("V3 unweighted Yes|Partly %s CI_low", r$Metric), r$CI_low, v3, "Summary", "")
      add2(sprintf("V3 unweighted Yes|Partly %s CI_high", r$Metric), r$CI_high, v3, "Summary", "")
    }
  }
  x <- w[grepl("without V7", as.character(w$Frame)) & w$`Reviewer CHD =` == "Yes|Partly", ]
  estcol <- if ("Weighted estimate" %in% names(x)) "Weighted estimate" else "Estimate"
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    add2(sprintf("V3 weighted excluding V7 Yes|Partly %s", r$Metric), r[[estcol]], v3, "Weighted_with_without_V7",
         if (!is.na(r$CI_low)) sprintf("CI %s to %s", r$CI_low, r$CI_high) else "")
    if (!is.na(r$CI_low)) {
      add2(sprintf("V3 weighted excluding V7 Yes|Partly %s CI_low", r$Metric), r$CI_low, v3, "Weighted_with_without_V7", "")
      add2(sprintf("V3 weighted excluding V7 Yes|Partly %s CI_high", r$Metric), r$CI_high, v3, "Weighted_with_without_V7", "")
    }
  }
  s4 <- as.data.frame(readxl::read_excel(v4, "Summary"))
  for (wn in c("unweighted", "weighted")) {
    u4 <- s4[s4$`Reviewer CHD =` == "Yes|Partly" & s4$Weighting == wn & grepl("all strata", as.character(s4$Frame)), ]
    prefix <- if (wn == "unweighted") "V4 unweighted Yes|Partly" else "V4 weighted all strata Yes|Partly"
    note0 <- if (wn == "unweighted") "n=198 after 2 Unsure excluded" else ""
    for (i in seq_len(nrow(u4))) {
      r <- u4[i, ]
      add2(sprintf("%s %s", prefix, r$Metric), r$Estimate, v4, "Summary",
           if (!is.na(r$CI_low)) sprintf("CI %s to %s", r$CI_low, r$CI_high) else note0)
      if (!is.na(r$CI_low)) {
        add2(sprintf("%s %s CI_low", prefix, r$Metric), r$CI_low, v4, "Summary", "")
        add2(sprintf("%s %s CI_high", prefix, r$Metric), r$CI_high, v4, "Summary", "")
      }
    }
  }
  ce <- as.data.frame(readxl::read_excel(comb, "Combined_estimate"))
  ce <- ce[ce$`Reviewer CHD =` == "Yes|Partly", ]
  for (i in seq_len(nrow(ce))) {
    r <- ce[i, ]
    add2(sprintf("Combined estimate Yes|Partly %s", r$Metric), r$Estimate, comb, "Combined_estimate",
         if (!is.na(r$CI_low)) sprintf("CI %s to %s", r$CI_low, r$CI_high) else "v1 833 tier-1 census + v2 fresh 200")
    if (!is.na(r$CI_low)) {
      add2(sprintf("Combined estimate Yes|Partly %s CI_low", r$Metric), r$CI_low, comb, "Combined_estimate", "")
      add2(sprintf("Combined estimate Yes|Partly %s CI_high", r$Metric), r$CI_high, comb, "Combined_estimate", "")
    }
  }
  a3 <- as.data.frame(readxl::read_excel(v3, "Age"))[1, ]
  add2("V3 age agreement n", a3$n, v3, "Age", "age-focus agreement among grants with an age label")
  add2("V3 age agreement", a3$Agreement, v3, "Age", "")
  add2("V3 age kappa", a3$Kappa, v3, "Age", "")
  a4 <- as.data.frame(readxl::read_excel(v4, "Age"))[1, ]
  add2("V4 age agreement n used", a4$`n used for agreement`, v4, "Age", "V4 is a clear-case CHD set; age kappa is weak")
  add2("V4 age agreement", a4$Agreement, v4, "Age", "V4 Notes sheet still says 'v2.3 pipeline'; counts are v2.4")
  add2("V4 age kappa", a4$Kappa, v4, "Age", "V4 Notes sheet still says 'v2.3 pipeline'; counts are v2.4")
  recs
}

build_key_numbers <- function(D, age, trends, W, mort_tr, O, periods, proj, xlsx_name,
                              score_dir = "outputs/v2.4") {
  src_xlsx <- file.path("outputs/v2.4/figures_tables", xlsx_name)
  recs <- list()
  add <- function(section, item, value, window, unit, sheet, note = "") {
    recs <<- c(recs, list(list(section = section, item = item, value = value, window = window,
                               unit = unit, source_file = src_xlsx, source_sheet = sheet, note = note)))
  }
  rowfy <- function(fy) D[D$FY == fy, ][1, ]
  trend <- function(name) {
    s <- trends[trends$series == name, ]
    if (!nrow(s)) NULL else s[1, ]
  }
  age_usd <- function(fy, a) {
    s <- age[age$FY == fy & age$age == a, ]
    if (nrow(s)) as.numeric(s$USD_M[1]) else 0
  }
  age_pct <- function(fy, a) {
    s <- age[age$FY == fy & age$age == a, ]
    if (nrow(s)) as.numeric(s$pct_of_CHD[1]) else 0
  }
  for (fy in 2013:2026) {
    r <- rowfy(fy); note <- if (fy == 2026) "PARTIAL fiscal year" else ""
    add("Funding", sprintf("CHD dollars FY%d", fy), r$CHD_USD_M, sprintf("FY%d", fy), "$ millions, nominal", "Yearly_v2.4", note)
    add("Funding", sprintf("CHD project-years FY%d", fy), r$CHD_projects, sprintf("FY%d", fy), "n", "Yearly_v2.4", note)
    add("Shares", sprintf("CHD %% of all NIH FY%d", fy), r$CHD_pct_of_NIH, sprintf("FY%d", fy), "percent", "Yearly_v2.4", note)
    add("Shares", sprintf("CHD %% of NIH CVD (nested) FY%d", fy), r$CHD_pct_of_CVD, sprintf("FY%d", fy), "percent", "Yearly_v2.4", note)
    add("Shares", sprintf("All-CHD %% of NIH CVD FY%d", fy), r$CHDall_pct_of_CVD, sprintf("FY%d", fy), "percent", "Yearly_v2.4", note)
    add("Shares", sprintf("CHD within CVD dollars FY%d", fy), r$CHD_in_CVD_USD_M, sprintf("FY%d", fy), "$ millions, nominal", "Yearly_v2.4", note)
    for (a in AGE_LEVELS_V24) {
      add("Age", sprintf("%s dollars FY%d", a, fy), age_usd(fy, a), sprintf("FY%d", fy), "$ millions, nominal", "Age_USD_M_v2.4", "v2.4 4-level age_v2; all combined CHD")
      add("Age", sprintf("%s share of CHD $ FY%d", a, fy), age_pct(fy, a), sprintf("FY%d", fy), "percent of CHD $", "Age_pct_v2.4", "v2.4 4-level age_v2")
    }
  }
  d13 <- rowfy(2013); d25 <- rowfy(2025)
  peak <- D[D$FY >= 2013 & D$FY <= 2025, ]
  p <- peak[which.max(peak$CHD_USD_M), ]
  add("Funding", "Peak CHD $ year", as.integer(p$FY), "FY2013-2025", "fiscal year", "Yearly_v2.4", "")
  add("Funding", "Peak CHD $ value", as.numeric(p$CHD_USD_M), sprintf("FY%d", as.integer(p$FY)), "$ millions, nominal", "Yearly_v2.4", "")
  add("Funding", "FY2013-2025 percent change in CHD $", 100 * (d25$CHD_USD_M / d13$CHD_USD_M - 1),
      "FY2013-2025", "percent", "Yearly_v2.4", "100*(FY2025/FY2013 - 1)")
  add("Funding", "FY2013-2025 CHD project-years start, end",
      sprintf("%d to %d", as.integer(d13$CHD_projects), as.integer(d25$CHD_projects)),
      "FY2013-2025", "n", "Yearly_v2.4", "")
  w <- D[D$FY >= 2013 & D$FY <= 2025, ]
  add("Shares", "CHD % of NIH CVD (nested) min FY2013-2025", min(w$CHD_pct_of_CVD),
      sprintf("FY%d", as.integer(w$FY[which.min(w$CHD_pct_of_CVD)])), "percent", "Yearly_v2.4", "")
  add("Shares", "CHD % of NIH CVD (nested) max FY2013-2025", max(w$CHD_pct_of_CVD),
      sprintf("FY%d", as.integer(w$FY[which.max(w$CHD_pct_of_CVD)])), "percent", "Yearly_v2.4", "")
  add("Shares", "CHD % of all NIH min FY2013-2025", min(w$CHD_pct_of_NIH),
      sprintf("FY%d", as.integer(w$FY[which.min(w$CHD_pct_of_NIH)])), "percent", "Yearly_v2.4", "")
  add("Shares", "CHD % of all NIH max FY2013-2025", max(w$CHD_pct_of_NIH),
      sprintf("FY%d", as.integer(w$FY[which.max(w$CHD_pct_of_NIH)])), "percent", "Yearly_v2.4", "")
  series_map <- c(
    "CHD all ($M) [v2.4 combined]" = "CHD dollars",
    "CHD % of NIH [v2.4 combined]" = "CHD % of all NIH",
    "CHD within CVD ($M) [v2.4 combined]" = "CHD within CVD dollars",
    "CHD % of CVD [v2.4 combined]" = "CHD % of NIH CVD (nested)",
    "Total NIH ($B)" = "Total NIH dollars",
    "Total CVD ($B)" = "Total NIH CVD dollars",
    "CVD % of NIH" = "CVD % of NIH",
    "CHD, RCDC ($M; FY2016-2025)" = "RCDC CHD dollars",
    "CHD % of NIH (RCDC; FY2016-2025)" = "RCDC CHD % of NIH"
  )
  for (series in names(series_map)) {
    label <- unname(series_map[[series]]); tr <- trend(series); if (is.null(tr)) next
    add("Trends", sprintf("%s CAGR", label), tr$CAGR_pct, tr$years, "percent per year", "Trends_funding", "end/start over the window")
    add("Trends", sprintf("%s APC", label), tr$APC_pct, tr$years, "percent per year", "Trends_funding", "log-linear OLS")
    add("Trends", sprintf("%s APC 95%% CI low", label), tr$APC_lo, tr$years, "percent per year", "Trends_funding", "")
    add("Trends", sprintf("%s APC 95%% CI high", label), tr$APC_hi, tr$years, "percent per year", "Trends_funding", "")
    add("Trends", sprintf("%s APC p", label), tr$p, tr$years, "slope p-value", "Trends_funding", "")
  }
  for (a in AGE_LEVELS_V24) {
    for (kind in c("$M", "% of CHD $")) {
      tr <- trend(sprintf("CHD %s (%s) [v2.4 combined]", a, kind)); if (is.null(tr)) next
      note <- if (tr$n < 13) sprintf("n=%d years with value > 0", as.integer(tr$n)) else ""
      add("Age trends", sprintf("%s %s CAGR", a, kind), tr$CAGR_pct, tr$years, "percent per year", "Trends_funding", note)
      add("Age trends", sprintf("%s %s APC", a, kind), tr$APC_pct, tr$years, "percent per year", "Trends_funding", note)
      add("Age trends", sprintf("%s %s APC 95%% CI low", a, kind), tr$APC_lo, tr$years, "percent per year", "Trends_funding", "")
      add("Age trends", sprintf("%s %s APC 95%% CI high", a, kind), tr$APC_hi, tr$years, "percent per year", "Trends_funding", "")
      add("Age trends", sprintf("%s %s APC p", a, kind), tr$p, tr$years, "slope p-value", "Trends_funding", "")
    }
  }
  adult <- age[age$age == "Adult", ]
  add("Age", "Adult share of CHD $ maximum (any FY)", max(adult$pct_of_CHD),
      sprintf("FY%d", as.integer(adult$FY[which.max(adult$pct_of_CHD)])), "percent of CHD $", "Age_pct_v2.4", "")
  add("Age", "Adult dollars maximum (any FY)", max(adult$USD_M),
      sprintf("FY%d", as.integer(adult$FY[which.max(adult$USD_M)])), "$ millions, nominal", "Age_USD_M_v2.4", "")
  ped <- age[age$age == "Pediatric" & age$FY >= 2020 & age$FY <= 2024, ]
  add("Age", "Pediatric share of CHD $ min FY2020-2024", min(ped$pct_of_CHD),
      sprintf("FY%d", as.integer(ped$FY[which.min(ped$pct_of_CHD)])), "percent of CHD $", "Age_pct_v2.4", "")
  add("Age", "Pediatric share of CHD $ max FY2020-2024", max(ped$pct_of_CHD),
      sprintf("FY%d", as.integer(ped$FY[which.max(ped$pct_of_CHD)])), "percent of CHD $", "Age_pct_v2.4", "")
  ic <- ic_shares(proj)
  for (window in names(ic)) {
    d <- ic[[window]]
    add("IC", sprintf("NHLBI (HL) share of CHD $ %s", window), d$nhlbi_pct, window, "percent of CHD $",
        "Projects in outputs/v2.4/chd_v2_funding.xlsx", sprintf("NHLBI dollars %.4f of %.4f million", d$nhlbi, d$total))
  }
  ro <- rcdc_outside(O)
  add("RCDC", "Share of RCDC dollars outside v2.4 combined, FY2016-2025", ro$pct_rcdc_dollars_outside_v24,
      "FY2016-2025", "percent of RCDC $", "Overlap_v2.4_vs_RCDC",
      sprintf("RCDC-only %.4f of %.4f million", ro$rcdc_only_M, ro$rcdc_total_M))
  add("RCDC", "Share of v2.4 combined dollars also in RCDC, FY2016-2025", ro$pct_v24_dollars_inside_rcdc,
      "FY2016-2025", "percent of v2.4 $", "Overlap_v2.4_vs_RCDC", "")
  rcdc <- D[D$FY >= 2016 & D$FY <= 2025, ]
  add("RCDC", "RCDC CHD dollars minimum FY2016-2025", min(rcdc$rcdc_USD_M),
      sprintf("FY%d", as.integer(rcdc$FY[which.min(rcdc$rcdc_USD_M)])), "$ millions, nominal", "Yearly_v2.4", "RCDC is independent of the v2.4 rule")
  add("RCDC", "RCDC CHD dollars maximum FY2016-2025", max(rcdc$rcdc_USD_M),
      sprintf("FY%d", as.integer(rcdc$FY[which.max(rcdc$rcdc_USD_M)])), "$ millions, nominal", "Yearly_v2.4", "RCDC is independent of the v2.4 rule")
  add("RCDC", "RCDC % of NIH minimum FY2016-2025", min(rcdc$rcdc_pct_of_NIH),
      sprintf("FY%d", as.integer(rcdc$FY[which.min(rcdc$rcdc_pct_of_NIH)])), "percent", "Yearly_v2.4", "")
  add("RCDC", "RCDC % of NIH maximum FY2016-2025", max(rcdc$rcdc_pct_of_NIH),
      sprintf("FY%d", as.integer(rcdc$FY[which.max(rcdc$rcdc_pct_of_NIH)])), "percent", "Yearly_v2.4", "")
  Oo <- O[!is.na(O$FY), ]
  for (i in seq_len(nrow(Oo))) {
    r <- Oo[i, ]; fy <- as.integer(r$FY)
    add("RCDC", sprintf("FY%d both dollars", fy), r$both_M, sprintf("FY%d", fy), "$ millions", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d v2.4-only dollars", fy), r$classifier_only_M, sprintf("FY%d", fy), "$ millions", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d RCDC-only dollars", fy), r$rcdc_only_M, sprintf("FY%d", fy), "$ millions", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d both n", fy), r$both_n, sprintf("FY%d", fy), "project-years", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d v2.4-only n", fy), r$classifier_only_n, sprintf("FY%d", fy), "project-years", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d RCDC-only n", fy), r$rcdc_only_n, sprintf("FY%d", fy), "project-years", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d %% of v2.4 projects also in RCDC", fy), r$pct_classifier_in_rcdc, sprintf("FY%d", fy), "percent", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d %% of RCDC projects also in v2.4", fy), r$pct_rcdc_in_classifier, sprintf("FY%d", fy), "percent", "Overlap_v2.4_vs_RCDC", "")
    add("RCDC", sprintf("FY%d intersection-over-union (dollars)", fy), r$iou_dollars, sprintf("FY%d", fy), "index 0-1", "Overlap_v2.4_vs_RCDC", "")
  }
  for (i in seq_len(nrow(periods))) {
    r <- periods[i, ]
    add("Shares", sprintf("Pooled CHD %% of NIH CVD %s", r$period), r$CHD_pct_of_CVD, r$period, "percent", "CVD_periods_v2.4", "pooled dollars, not mean of yearly shares")
    add("Shares", sprintf("Pooled CHD %% of NIH %s", r$period), r$CHD_pct_of_NIH, r$period, "percent", "CVD_periods_v2.4", "pooled dollars, not mean of yearly shares")
  }
  w13 <- W[W$year == 2013, ][1, ]; w24 <- W[W$year == 2024, ][1, ]
  mort_range <- function(col, label, unit = "percent") {
    add("Mortality", sprintf("%s 2013", label), w13[[col]], "2013", unit, "Mortality_yearly", "Death counts unchanged from v1")
    add("Mortality", sprintf("%s 2024", label), w24[[col]], "2024", unit, "Mortality_yearly", "Death counts unchanged from v1")
    add("Mortality", sprintf("%s min 2013-2024", label), min(W[[col]]), sprintf("%d", as.integer(W$year[which.min(W[[col]])])), unit, "Mortality_yearly", "")
    add("Mortality", sprintf("%s max 2013-2024", label), max(W[[col]]), sprintf("%d", as.integer(W$year[which.max(W[[col]])])), unit, "Mortality_yearly", "")
  }
  mort_range("chd_ucd_pct_of_cvd_all", "CHD underlying-cause share of CVD deaths, all ages")
  mort_range("chd_any_pct_of_cvd_all", "CHD any-mention share of CVD deaths, all ages")
  mort_range("chd_ucd_pct_of_cvd_ped", "CHD underlying-cause share of CVD deaths, children (0-17)")
  mort_range("chd_any_pct_of_cvd_adult", "CHD any-mention share of CVD deaths, adults")
  mort_range("chd_ucd_pct_of_cvd_adult", "CHD underlying-cause share of CVD deaths, adults")
  add("Mortality", "Pediatric underlying-cause CHD deaths 2013", as.integer(w13$chd_ucd_ped), "2013", "deaths", "Mortality_yearly", "Unchanged from v1")
  add("Mortality", "Pediatric underlying-cause CHD deaths 2024", as.integer(w24$chd_ucd_ped), "2024", "deaths", "Mortality_yearly", "Unchanged from v1")
  add("Mortality", "Adult any-mention CHD deaths 2013", as.integer(w13$chd_any_adult), "2013", "deaths", "Mortality_yearly", "Unchanged from v1")
  add("Mortality", "Adult any-mention CHD deaths 2024", as.integer(w24$chd_any_adult), "2024", "deaths", "Mortality_yearly", "Unchanged from v1")
  add("Mortality", "Adult any-mention CHD deaths percent change 2013-2024",
      100 * (w24$chd_any_adult / w13$chd_any_adult - 1), "2013-2024", "percent", "Mortality_yearly", "100*(2024/2013 - 1)")
  name_map <- c(
    chd_ucd_ped = "Pediatric underlying-cause CHD deaths",
    chd_any_adult = "Adult any-mention CHD deaths",
    chd_ucd_pct_of_cvd_ped = "Pediatric UCD CHD share of CVD deaths",
    chd_any_pct_of_cvd_adult = "Adult any-mention CHD share of CVD deaths",
    chd_ucd_pct_of_cvd_all = "All-ages UCD CHD share of CVD deaths",
    chd_any_pct_of_cvd_all = "All-ages any-mention CHD share of CVD deaths",
    CHD_pct_of_CVD_funding = "CHD % of NIH CVD funding (aligned to mortality years)"
  )
  for (series in names(name_map)) {
    s <- mort_tr[mort_tr$series == series, ]; if (!nrow(s)) next
    tr <- s[1, ]; label <- unname(name_map[[series]])
    add("Mortality trends", sprintf("%s APC", label), tr$APC_pct, "2013-2024", "percent per year", "Mortality_trends",
        "v2.4 funding share on the funding series; death series unchanged from v1")
    add("Mortality trends", sprintf("%s APC 95%% CI low", label), tr$APC_lo, "2013-2024", "percent per year", "Mortality_trends", "")
    add("Mortality trends", sprintf("%s APC 95%% CI high", label), tr$APC_hi, "2013-2024", "percent per year", "Mortality_trends", "")
    add("Mortality trends", sprintf("%s APC p", label), tr$p, "2013-2024", "slope p-value", "Mortality_trends", "")
  }
  recs <- c(recs, val_rows_from_scoring(score_dir))
  # bind
  kn <- do.call(rbind, lapply(recs, function(x) {
    val <- x$value
    if (length(val) != 1) val <- val[1]
    data.frame(section = x$section, item = x$item, value = I(list(val)),
               window = x$window, unit = x$unit, source_file = x$source_file,
               source_sheet = x$source_sheet, note = x$note, stringsAsFactors = FALSE)
  }))
  kn$value_flat <- vapply(kn$value, function(z) {
    z <- z[[1]]
    if (is.null(z) || length(z) == 0) return(NA_character_)
    as.character(z)[1]
  }, character(1))
  kn
}

write_key_markdown <- function(kn, path) {
  lines <- c("# Key numbers (v2.4 combined CHD definition)", "",
             "Every citable value from the share, mortality, and validation tables, with its source.", "",
             "| Item | Value | Window | Unit | Source | Note |",
             "| --- | --- | --- | --- | --- | --- |")
  for (i in seq_len(nrow(kn))) {
    r <- kn[i, ]
    val <- r$value_flat
    lines <- c(lines, sprintf("| %s | %s | %s | %s | %s / %s | %s |",
                              r$item, val, r$window, r$unit, basename(r$source_file), r$source_sheet, r$note))
  }
  writeLines(lines, path)
}


chd_round_df <- function(df, nd = 4L, skip = character()) {
  out <- df
  for (nm in names(out)) {
    if (nm %in% skip) next
    x <- out[[nm]]
    if (is.numeric(x) && !is.integer(x)) out[[nm]] <- round(as.numeric(x), nd)
  }
  out
}

age_wide <- function(age_df, levels, val = "USD_M") {
  years <- sort(unique(as.integer(age_df$FY)))
  cols <- lapply(levels, function(a) {
    s <- age_df[as.character(age_df$age) == a, , drop = FALSE]
    v <- setNames(rep(0, length(years)), as.character(years))
    if (nrow(s)) v[as.character(s$FY)] <- as.numeric(s[[val]])
    v
  })
  out <- data.frame(FY = years, do.call(cbind, cols), check.names = FALSE, stringsAsFactors = FALSE)
  names(out) <- c("FY", levels)
  out
}

comparison_sheet <- function(D_v1, D_v24, trends_v1, trends_v24, age_v1, age_v24, mort_tr_v1, mort_tr_v24) {
  recs <- list(); k <- 1L
  add <- function(item, year, v1, v24, unit = "") {
    diff <- if (length(v1) == 1 && length(v24) == 1 && is.finite(v1) && is.finite(v24)) as.numeric(v24) - as.numeric(v1) else NA_real_
    recs[[k]] <<- data.frame(item = item, year_or_window = year, v1_keyword = v1,
                             `v2.4_combined` = v24, abs_diff_v24_minus_v1 = diff, unit = unit,
                             check.names = FALSE, stringsAsFactors = FALSE)
    k <<- k + 1L
  }
  age_pct <- function(age_df, fy, a) {
    s <- age_df[age_df$FY == fy & age_df$age == a, ]
    if (nrow(s)) as.numeric(s$pct_of_CHD[1]) else 0
  }
  age_usd <- function(age_df, fy, a) {
    s <- age_df[age_df$FY == fy & age_df$age == a, ]
    if (nrow(s)) as.numeric(s$USD_M[1]) else 0
  }
  age_pct_pooled <- function(age_df, a, fy_min = 2013, fy_max = 2026) {
    s <- age_df[age_df$FY >= fy_min & age_df$FY <= fy_max, ]
    tot <- sum(s$USD_M); sub <- sum(s$USD_M[s$age == a])
    if (tot) 100 * sub / tot else NA_real_
  }
  for (fy in 2013:2026) {
    a <- D_v1[D_v1$FY == fy, ][1, ]; b <- D_v24[D_v24$FY == fy, ][1, ]
    add("CHD dollars", sprintf("FY%d", fy), a$CHD_USD_M, b$CHD_USD_M, "$ millions, nominal")
    add("CHD project-years", sprintf("FY%d", fy), a$CHD_projects, b$CHD_projects, "n")
    add("CHD % of all NIH", sprintf("FY%d", fy), a$CHD_pct_of_NIH, b$CHD_pct_of_NIH, "percent")
    add("CHD % of NIH CVD (nested)", sprintf("FY%d", fy), a$CHD_pct_of_CVD, b$CHD_pct_of_CVD, "percent")
    add("All-CHD % of NIH CVD", sprintf("FY%d", fy), a$CHDall_pct_of_CVD, b$CHDall_pct_of_CVD, "percent")
    add("CHD within CVD dollars", sprintf("FY%d", fy), a$CHD_in_CVD_USD_M, b$CHD_in_CVD_USD_M, "$ millions, nominal")
    add("NIH total", sprintf("FY%d", fy), a$NIH_USD_B, b$NIH_USD_B, "$ billions, nominal (denominator, unchanged)")
    add("NIH CVD total", sprintf("FY%d", fy), a$CVD_USD_B, b$CVD_USD_B, "$ billions, nominal (denominator, unchanged)")
  }
  for (fy in c(2013, 2025, 2026)) {
    for (a in c("Pediatric", "Adult", "Both")) {
      add(sprintf("Age share of CHD $: %s", a), sprintf("FY%d", fy), age_pct(age_v1, fy, a), age_pct(age_v24, fy, a), "percent of CHD $")
      add(sprintf("Age dollars: %s", a), sprintf("FY%d", fy), age_usd(age_v1, fy, a), age_usd(age_v24, fy, a), "$ millions, nominal")
    }
    add("Age share of CHD $: Basic/non-age-specific (v1 only)", sprintf("FY%d", fy), age_pct(age_v1, fy, "Basic/non-age-specific"), NA_real_, "percent of CHD $")
    add("Age share of CHD $: Unclear (v1 only)", sprintf("FY%d", fy), age_pct(age_v1, fy, "Unclear"), NA_real_, "percent of CHD $")
    add("Age share of CHD $: Not age-specific (v2.4 only)", sprintf("FY%d", fy), NA_real_, age_pct(age_v24, fy, "Not age-specific"), "percent of CHD $")
  }
  for (a in c("Pediatric", "Adult", "Both")) {
    add(sprintf("Age share of CHD $: %s", a), "FY2013-2026 pooled", age_pct_pooled(age_v1, a), age_pct_pooled(age_v24, a), "percent of CHD $")
  }
  add("Age share of CHD $: Basic/non-age-specific (v1 only)", "FY2013-2026 pooled", age_pct_pooled(age_v1, "Basic/non-age-specific"), NA_real_, "percent of CHD $")
  add("Age share of CHD $: Unclear (v1 only)", "FY2013-2026 pooled", age_pct_pooled(age_v1, "Unclear"), NA_real_, "percent of CHD $")
  add("Age share of CHD $: Not age-specific (v2.4 only)", "FY2013-2026 pooled", NA_real_, age_pct_pooled(age_v24, "Not age-specific"), "percent of CHD $")
  tmap <- list(
    c("CHD all ($M) [v1 keyword]", "CHD all ($M) [v2.4 combined]", "APC, CHD dollars, FY2013-2025"),
    c("CHD % of NIH [v1 keyword]", "CHD % of NIH [v2.4 combined]", "APC, CHD % of NIH, FY2013-2025"),
    c("CHD within CVD ($M) [v1 keyword]", "CHD within CVD ($M) [v2.4 combined]", "APC, CHD within CVD $, FY2013-2025"),
    c("CHD % of CVD [v1 keyword]", "CHD % of CVD [v2.4 combined]", "APC, CHD % of CVD, FY2013-2025"),
    c("CHD Pediatric ($M) [v1 keyword]", "CHD Pediatric ($M) [v2.4 combined]", "APC, Pediatric CHD $, FY2013-2025"),
    c("CHD Adult ($M) [v1 keyword]", "CHD Adult ($M) [v2.4 combined]", "APC, Adult CHD $, FY2013-2025"),
    c("CHD Both ($M) [v1 keyword]", "CHD Both ($M) [v2.4 combined]", "APC, Both-ages CHD $, FY2013-2025"),
    c("CHD Pediatric (% of CHD $) [v1 keyword]", "CHD Pediatric (% of CHD $) [v2.4 combined]", "APC, Pediatric share of CHD $, FY2013-2025"),
    c("CHD Adult (% of CHD $) [v1 keyword]", "CHD Adult (% of CHD $) [v2.4 combined]", "APC, Adult share of CHD $, FY2013-2025"),
    c("CHD Both (% of CHD $) [v1 keyword]", "CHD Both (% of CHD $) [v2.4 combined]", "APC, Both-ages share of CHD $, FY2013-2025")
  )
  for (tm in tmap) {
    g <- trends_v1[trends_v1$series == tm[1], ]; h <- trends_v24[trends_v24$series == tm[2], ]
    if (!nrow(g) || !nrow(h)) next
    g <- g[1, ]; h <- h[1, ]
    add(sprintf("%s (APC)", tm[3]), g$years, g$APC_pct, h$APC_pct, "percent per year")
    add(sprintf("%s (APC lo)", tm[3]), g$years, g$APC_lo, h$APC_lo, "percent per year")
    add(sprintf("%s (APC hi)", tm[3]), g$years, g$APC_hi, h$APC_hi, "percent per year")
    add(sprintf("%s (p)", tm[3]), g$years, g$p, h$p, "slope p-value")
    add(sprintf("%s (CAGR)", tm[3]), g$years, g$CAGR_pct, h$CAGR_pct, "percent per year")
  }
  if (!is.null(mort_tr_v1) && !is.null(mort_tr_v24)) {
    g <- mort_tr_v1[mort_tr_v1$series == "CHD_pct_of_CVD_funding", ]
    h <- mort_tr_v24[mort_tr_v24$series == "CHD_pct_of_CVD_funding", ]
    if (nrow(g) && nrow(h)) {
      g <- g[1, ]; h <- h[1, ]
      add("APC, CHD % of CVD funding (aligned to mortality years)", "2013-2024", g$APC_pct, h$APC_pct, "percent per year")
      add("APC lo, CHD % of CVD funding (mortality years)", "2013-2024", g$APC_lo, h$APC_lo, "percent per year")
      add("APC hi, CHD % of CVD funding (mortality years)", "2013-2024", g$APC_hi, h$APC_hi, "percent per year")
      add("p, CHD % of CVD funding (mortality years)", "2013-2024", g$p, h$p, "slope p-value")
    }
  }
  peak <- function(D) {
    s <- D[D$FY >= 2013 & D$FY <= 2025, ]
    i <- which.max(s$CHD_USD_M)
    list(y = as.integer(s$FY[i]), v = as.numeric(s$CHD_USD_M[i]))
  }
  p1 <- peak(D_v1); p2 <- peak(D_v24)
  add("Peak CHD $ year (FY2013-2025)", "FY2013-2025", p1$y, p2$y, "fiscal year")
  add("Peak CHD $ value (FY2013-2025)", sprintf("v1 FY%d; v2.4 FY%d", p1$y, p2$y), p1$v, p2$v, "$ millions, nominal")
  v1_13 <- D_v1$CHD_USD_M[D_v1$FY == 2013][1]; v1_25 <- D_v1$CHD_USD_M[D_v1$FY == 2025][1]
  v24_13 <- D_v24$CHD_USD_M[D_v24$FY == 2013][1]; v24_25 <- D_v24$CHD_USD_M[D_v24$FY == 2025][1]
  add("FY2013-2025 dollar change", "FY2025 minus FY2013", v1_25 - v1_13, v24_25 - v24_13, "$ millions, nominal")
  add("FY2013-2025 percent change in CHD $", "100*(FY2025/FY2013 - 1)", 100 * (v1_25 / v1_13 - 1), 100 * (v24_25 / v24_13 - 1), "percent")
  do.call(rbind, recs)
}

README_ROWS <- data.frame(
  Item = c("Purpose","CHD definition","Universe / denominators","CHD % of CVD","Dollars","FY2026","Age focus","Trends","Mortality","Funding vs mortality","Self-check","Figures","Inflation"),
  Text = c(
    "v2.4 combined (Tier 1 + Tier 2) CHD funding shares of NIH CVD and of all NIH, age split, APCs, and a funding-vs-mortality comparison. New outputs only; v1 and earlier v2.x files were not overwritten.",
    "v2.4 combined = Tier 1 CHD-focused + Tier 2 CHD-related basic/developmental science, from outputs/v2.4/chd_v2_funding.xlsx (Projects sheet). Rules were not changed in this run.",
    "Yearly NIH and CVD denominators in data/work/nih_cvd_yearly.csv were aggregated from the same cached grant universe used by R/07_cvd.R (one record per full project number per fiscal year, parent-award total cost, and the same CVD flag). The de-identified NIH IC project-year universe and v1 CVD flags used for these denominators are shipped in data/shipped/ and rebuilt by R/run_all_v2.4.R. assemble.py was not run.",
    "Numerator = v2.4 combined projects that also meet the CVD definition (nested). CHDall % of CVD (all combined dollars / CVD) is also reported.",
    "Nominal parent-award total cost (direct + indirect). The v1 pipeline did not inflation-adjust; no deflator series is included.",
    "Partial fiscal year (records retrieved 2026-10-20). Shown in yearly tables and figures (lighter) but excluded from APC/CAGR (FY2013-2025), matching the FY2013-2025 window used for the v1 tables.",
    "v2.4 4-level: Pediatric / Adult / Both / Not age-specific (age_v2). v1 used a 5-level scheme (Pediatric / Adult / Both / Basic/non-age-specific / Unclear); those v1 categories are on the comparison sheet only.",
    "Log-linear OLS of log(value) on year; APC = 100*(exp(slope)-1) with 95% t-interval and slope p, as in R/05_analysis.R and R/07_cvd.R. CAGR uses end/start over the same window.",
    "US deaths 2013-2024 from cached CDC WONDER files in data/wonder (no refetch): D76/D77 bridged-race final for 2013-2017; D158/D157 single-race final for 2018-2024. CHD = ICD-10 Q20-Q26 as underlying cause or any mention. Denominators = underlying-cause CVD (I00-I99) or heart disease, each plus underlying-cause CHD. Pediatric = ages 0-17; adult = all ages minus pediatric (includes age not stated). Counts are unchanged from v1.",
    "v1 reported the CHD share of NIH CVD funding (nested numerator) alongside mortality shares; it did not compute a dollars-per-death ratio. The same share ratio is used here, with the v2.4 nested CHD % of CVD.",
    "This script first rebuilds v1 keyword shares from the shipped yearly denominators and v1 keyword numerators and compares them to data/work/v1_expected_*.csv (including CHD % of CVD 2.2124 in FY2013 and 2.1654 in FY2025, and CHD % of NIH 0.2257 to 0.2033). See Self_check.",
    "PNG/PDF analogs of the v1 Fig1-Fig8 series and a two-panel main figure (PNG+TIF, 300 dpi) are in this folder. They use v2.4 combined dollars and shares; mortality panels use the unchanged death counts.",
    "Not applied (v1 used nominal dollars only)."
  ), stringsAsFactors = FALSE)

run_v24_shares <- function(out_dir = "outputs/v2.4/figures_tables",
                           funding_xlsx = "outputs/v2.4/chd_v2_funding.xlsx",
                           score_dir = "outputs/v2.4") {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  denoms <- load_denominators()
  proj <- load_v24_projects(funding_xlsx)
  D_v1 <- yearly_v1(denoms)
  D_v24 <- yearly_v24(denoms, proj)
  age_v1 <- age_from_v1()
  age_v24 <- age_from_v24(proj)
  mort <- mortality_from_wonder()
  W <- mort$W
  # align funding share onto mortality years for the funding-vs-deaths trend
  W <- merge(W, D_v24[, c("FY", "CHD_pct_of_CVD")], by.x = "year", by.y = "FY", all.x = TRUE)
  names(W)[names(W) == "CHD_pct_of_CVD"] <- "CHD_pct_of_CVD_funding"
  O_v24 <- overlap_vs_rcdc(proj)
  trends_v1 <- funding_trends(D_v1, age_v1, c("Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear"), "v1 keyword")
  trends_v24 <- funding_trends(D_v24, age_v24, AGE_LEVELS_V24, "v2.4 combined")
  mort_tr_v24 <- mortality_trends(W)
  periods_v24 <- rbind(
    period_pooled(D_v24, 2013:2015, "FY2013-2015"),
    period_pooled(D_v24, 2023:2025, "FY2023-2025")
  )
  sc <- self_check_v1(D_v1, age_v1, W, trends_v1, file.path(out_dir, "self_check_v1.txt"))
  if (!sc$ok) stop("v1 self-check failed; see ", file.path(out_dir, "self_check_v1.txt"))
  kn <- build_key_numbers(D_v24, age_v24, trends_v24, W, mort_tr_v24, O_v24, periods_v24, proj,
                          "chd_v2.4_shares_mortality.xlsx", score_dir = score_dir)
  write_key_markdown(kn, file.path(out_dir, "key_numbers_v2.4.md"))
  age_incvd <- age_from_v24(proj, in_cvd = TRUE)
  # v1 mortality-window funding share, for the comparison sheet only
  W1 <- W
  W1$CHD_pct_of_CVD_funding <- NULL
  W1 <- merge(W1, D_v1[, c("FY", "CHD_pct_of_CVD")], by.x = "year", by.y = "FY", all.x = TRUE)
  names(W1)[names(W1) == "CHD_pct_of_CVD"] <- "CHD_pct_of_CVD_funding"
  mort_tr_v1 <- mortality_trends(W1)
  trends_all <- rbind(trends_v1, trends_v24)
  compare <- comparison_sheet(D_v1, D_v24, trends_v1, trends_v24, age_v1, age_v24, mort_tr_v1, mort_tr_v24)
  check_df <- data.frame(line = strsplit(sc$text, "\n", fixed = TRUE)[[1]], stringsAsFactors = FALSE)

  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("openxlsx is required")
  wb <- openxlsx::createWorkbook()
  add <- function(name, df) {
    openxlsx::addWorksheet(wb, name)
    openxlsx::writeData(wb, name, df)
  }
  add("README", README_ROWS)
  lv24 <- c("Pediatric", "Adult", "Both", "Not age-specific")
  lv1 <- c("Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear")
  add("Yearly_v2.4", chd_round_df(D_v24))
  add("Yearly_v1_keyword", chd_round_df(D_v1))
  add("Age_USD_M_v2.4", chd_round_df(age_wide(age_v24, lv24)))
  add("Age_pct_v2.4", chd_round_df(age_wide(age_v24, lv24, "pct_of_CHD")))
  add("Age_in_CVD_USD_M_v2.4", chd_round_df(age_wide(age_incvd, lv24)))
  add("Age_USD_M_v1", chd_round_df(age_wide(age_v1, lv1)))
  add("Overlap_v2.4_vs_RCDC", chd_round_df(O_v24))
  add("CVD_periods_v2.4", chd_round_df(periods_v24))
  add("Trends_funding", chd_round_df(trends_all))
  add("Mortality_yearly", chd_round_df(W, skip = "year"))
  add("Mortality_trends", chd_round_df(mort_tr_v24))
  add("Mortality_splice_check", mort$ov)
  add("v1_vs_v2.4", chd_round_df(compare))
  knw <- kn
  knw$value <- knw$value_flat
  knw$value_flat <- NULL
  add("Key_numbers", knw)
  add("Self_check", check_df)
  openxlsx::saveWorkbook(wb, file.path(out_dir, "chd_v2.4_shares_mortality.xlsx"), overwrite = TRUE)
  # cache tables for figures
  saveRDS(list(D_v1 = D_v1, D_v24 = D_v24, age_v1 = age_v1, age_v24 = age_v24,
               age_incvd = age_incvd,
               W = W, O_v24 = O_v24, trends_v1 = trends_v1, trends_v24 = trends_v24,
               mort_tr = mort_tr_v24, periods = periods_v24, kn = kn, proj = proj),
          file.path(out_dir, "_tables.rds"))
  cat("Wrote shares workbook and key numbers (", nrow(kn), " rows). Self-check: ALL CHECKS PASSED\n", sep = "")
  invisible(list(D_v24 = D_v24, age_v24 = age_v24, trends_v24 = trends_v24,
                 W = W, O = O_v24, kn = kn, ok = TRUE))
}

if (identical(environment(), globalenv()) && !interactive() &&
    any(grepl("26_v24_shares\\.R$", commandArgs(trailingOnly = FALSE)))) {
  setwd(chd_root())
  run_v24_shares()
}
