#' 05_analysis.R -- yearly CHD funding, age split, trends, top ICs, classifier comparison and
#' validation metrics. Writes outputs/chd_nih_funding_2013_2026.xlsx and data/work/tables.rds.
#' Dollars are nominal total costs (direct + indirect). FY2026 is PARTIAL (records as of
#' 2026-10-20) and is excluded from all trend statistics.
source("R/00_setup.R")
C <- readRDS(wp("C.rds"))
S <- readRDS(wp("sample.rds")); source("data/validation/review_judgments.R")

# ---- 1. yearly totals: NIH denominator and keyword-CHD numerator --------------------------------
tot <- C[, .(nih_projects = .N, nih_USD_B = sum(USD) / 1e9), by = FY]
chd <- C[kw == TRUE, .(chd_projects = .N, chd_USD_M = sum(USD) / 1e6), by = FY]
Y <- merge(tot, chd, by = "FY")
Y[, chd_pct_of_NIH := 100 * chd_USD_M / (nih_USD_B * 1e3)]
rc <- C[, .(rcdc_projects = sum(rcdc & rcdc_avail), rcdc_USD_M = sum(USD[rcdc & rcdc_avail]) / 1e6,
            union_projects = sum(union), union_USD_M = sum(USD[union]) / 1e6), by = FY]
Y <- merge(Y, rc, by = "FY")
Y[!FY %in% 2016:2025, `:=`(rcdc_projects = NA, rcdc_USD_M = NA, union_projects = NA, union_USD_M = NA)]
Y[, `:=`(rcdc_pct_of_NIH = 100 * rcdc_USD_M / (nih_USD_B * 1e3), union_pct_of_NIH = 100 * union_USD_M / (nih_USD_B * 1e3))]
Y[, note := fifelse(FY == 2026, "PARTIAL fiscal year (records as of 2026-10-20); RCDC not yet assigned",
             fifelse(FY < 2016, "RCDC CHD category not available before FY2016", ""))]

# ---- 2. age split (keyword CHD) -------------------------------------------------------------------
A <- C[kw == TRUE, .(projects = .N, USD_M = sum(USD) / 1e6), by = .(FY, age)]
A[, pct_of_CHD := 100 * USD_M / sum(USD_M), by = FY]
A <- merge(A, tot[, .(FY, nih_USD_B)], by = "FY")
A[, pct_of_NIH := 100 * USD_M / (nih_USD_B * 1e3)][, nih_USD_B := NULL]
setorder(A, FY, age)
Aw <- dcast(A, FY ~ age, value.var = "USD_M", fill = 0)
Ap <- dcast(A, FY ~ age, value.var = "pct_of_CHD", fill = 0)
An <- dcast(A, FY ~ age, value.var = "projects", fill = 0)
# clinically age-specific dollars only (Pediatric vs Adult among those two; Both shown separately)

# ---- 3. trends FY2013-2025: CAGR and log-linear slope (annual % change, 95% CI) -----------------
trend <- function(y, v, lab) {
  d <- data.table(y = y, v = v)[y %in% CONFIG$trend_years & v > 0]
  f <- lm(log(v) ~ y, data = d); b <- coef(f)[2]; ci <- confint(f)[2, ]
  first <- d[y == min(y), v]; last <- d[y == max(y), v]
  data.table(series = lab, years = sprintf("FY%d-%d", min(d$y), max(d$y)),
             start = first, end = last, CAGR_pct = 100 * ((last / first)^(1 / (max(d$y) - min(d$y))) - 1),
             APC_pct = 100 * (exp(b) - 1), APC_lo = 100 * (exp(ci[1]) - 1), APC_hi = 100 * (exp(ci[2]) - 1),
             p = summary(f)$coefficients[2, 4])
}
Tr <- rbind(trend(Y$FY, Y$nih_USD_B * 1e3, "Total NIH ($M)"),
            trend(Y$FY, Y$chd_USD_M, "CHD, keyword ($M)"),
            trend(Y$FY, Y$chd_pct_of_NIH, "CHD % of NIH (keyword)"),
            trend(Y$FY, Y$rcdc_USD_M, "CHD, RCDC ($M; FY2016-2025)"),
            trend(Y$FY, Y$rcdc_pct_of_NIH, "CHD % of NIH (RCDC; FY2016-2025)"),
            rbindlist(lapply(levels(C$age), function(a) trend(Aw$FY, Aw[[a]], paste0("CHD ", a, " ($M)")))))

# ---- 4. top administering ICs (keyword CHD, FY2013-2026 pooled and FY2013-2025) ------------------
IC <- C[kw == TRUE, .(projects = .N, USD_M = sum(USD) / 1e6), by = IC][order(-USD_M)]
IC[, pct_of_CHD := 100 * USD_M / sum(USD_M)]
ICy <- dcast(C[kw == TRUE, .(USD_M = sum(USD) / 1e6), by = .(FY, IC)], IC ~ FY, value.var = "USD_M", fill = 0)
ic_order <- IC[["IC"]]; ICy <- ICy[match(ic_order, ICy[["IC"]])]
ACT <- C[kw == TRUE, .(projects = .N, USD_M = sum(USD) / 1e6), by = .(mech = substr(ACT, 1, 1))][order(-USD_M)]

# ---- 5. keyword vs RCDC overlap, FY2016-2025 ----------------------------------------------------
O <- C[rcdc_avail == TRUE, .(both_n = sum(kw & rcdc), kw_only_n = sum(kw & !rcdc), rcdc_only_n = sum(rcdc & !kw),
                              both_M = sum(USD[kw & rcdc]) / 1e6, kw_only_M = sum(USD[kw & !rcdc]) / 1e6,
                              rcdc_only_M = sum(USD[rcdc & !kw]) / 1e6), by = FY]
O <- rbind(O, O[, c(list(FY = NA_integer_), lapply(.SD, sum)), .SDcols = -"FY"])
O[, `:=`(jaccard_projects = both_n / (both_n + kw_only_n + rcdc_only_n),
         pct_kw_in_rcdc = 100 * both_n / (both_n + kw_only_n), pct_rcdc_in_kw = 100 * both_n / (both_n + rcdc_only_n),
         jaccard_dollars = both_M / (both_M + kw_only_M + rcdc_only_M))]
# API vs bulk-file RCDC agreement (application level, years with both)
AG <- C[FY %in% c(2016:2022, 2024:2025), .(projects = .N, disagree = sum(rcdc_file != rcdc_api))]

# ---- 6. validation ----------------------------------------------------------------------------
S[, k := as.integer(sub(".*_", "", id))]
S[, chd_judge := "yes"]
for (s in names(chd_no)) S[set == s & k %in% chd_no[[s]], chd_judge := "no"]
for (s in names(chd_partial)) S[set == s & k %in% chd_partial[[s]], chd_judge := "partial"]
S[set == "S4_age", age_ok := !k %in% age_wrong]
V <- S[set != "S4_age", .(n = .N, yes = sum(chd_judge == "yes"), partial = sum(chd_judge == "partial"), no = sum(chd_judge == "no"),
                          USD_M = sum(USD) / 1e6, USD_yes_or_partial_M = sum(USD[chd_judge != "no"]) / 1e6), by = set]
V[, `:=`(strict_pct = 100 * yes / n, lenient_pct = 100 * (yes + partial) / n)]
VA <- S[set == "S4_age", .(n = .N, correct = sum(age_ok), pct_correct = 100 * mean(age_ok)), by = .(assigned = age)]
VA <- rbind(VA, data.table(assigned = "All", n = sum(VA$n), correct = sum(VA$correct), pct_correct = 100 * sum(VA$correct) / sum(VA$n)))
# De-identified review list: titles, labels, judgments only (no abstracts, no investigator fields)
Vlist <- S[, .(sample = set, id, FY, IC, activity = ACT, USD_M = round(USD / 1e6, 3), title,
               keyword_CHD = kw, RCDC_CHD = rcdc, age_assigned = age, CHD_judgment = fifelse(set == "S4_age", NA_character_, chd_judge), age_correct = age_ok)]

# ---- 7. de-identified project list (keyword CHD) ---------------------------------------------------
L <- C[kw == TRUE, .(FY, project_number = FULL_PROJECT_NUM, IC, activity = ACT, USD = round(USD), title,
                     RCDC_CHD = fifelse(rcdc_avail, as.character(rcdc), "n/a"), age_group = age,
                     strong_title = t_str, strong_text = s_str, weak_text = s_weak, ped_mentions = s_ped,
                     adult_mentions = s_adu, basic_mentions = s_basic, clinical_mentions = s_hum)][order(FY, -USD)]

saveRDS(list(Y = Y, A = A, Aw = Aw, Ap = Ap, Tr = Tr, IC = IC, O = O, V = V, VA = VA), wp("tables.rds"))

# ---- 8. workbook ---------------------------------------------------------------------------------
rules <- data.table(item = c(
  "Universe / denominator", "Dollars", "Keyword CHD (primary)", "RCDC CHD", "Union", "Pediatric", "Adult", "Both",
  "Basic/non-age-specific", "Unclear", "Trends", "FY2026", "Sources"), rule = c(
  "All projects administered by an NIH Institute/Center, one record per full project number per fiscal year (identical to the women's health research pipeline); FY2020/2024 intramural projects use RePORTER-API abstracts.",
  "Parent-record total cost (direct + indirect), else summed component costs; nominal US dollars; components never double counted.",
  ">=1 strong CHD term in the title, OR >=3 strong-term mentions in title+abstract+public health relevance text, OR 2 strong + >=2 weak mentions, OR >=1 strong mention with a pediatric-cardiac title. Strong terms name CHD or specific lesions (Fontan, single ventricle, HLHS, tetralogy of Fallot, TGA, coarctation, septal defects, Ebstein, truncus, DORV, atresias, TAPVR, heterotaxy, conotruncal, ACHD...). Bare 'CHD' and 'ASD/VSD' abbreviations are not used (coronary heart disease, autism, voltage-sensing domain).",
  "NIH RCDC spending category 'Congenital Heart Disease' (RePORTER id 3533) on any record of the project; FY2016-2025 only (FY2023 from the RePORTER API because the bulk file lacks RCDC).",
  "Keyword OR RCDC (FY2016-2025 sensitivity).",
  "Pediatric term in title, or >=2 pediatric/fetal/neonatal mentions, and adult criteria not met.",
  "Adult-CHD term in title (ACHD, adults with...), or >=2 adult-population mentions ('adult mice', 'adult stem cells' etc. excluded), and pediatric criteria not met.",
  "Both pediatric and adult criteria met, or an explicit both-ages phrase ('children and adults').",
  "Checked first: no age term in title, >=3 basic-science mentions (animal models, embryos, iPSC, developmental pathways) and more basic-science than clinical mentions; also projects with no age signal but >=3 basic mentions.",
  "None of the above (eg, devices, imaging, genetics with no stated age group).",
  "FY2013-2025: compound annual growth rate (end/start) and log-linear regression slope expressed as annual % change with 95% CI. FY2026 excluded.",
  "Partial year (records retrieved 2026-10-20); shown but not used in trends; RCDC not yet assigned.",
  "FY2013-2025 NIH ExPORTER project/abstract files; FY2026 and RCDC lists from the RePORTER API v2."))
wb <- createWorkbook(); hs <- createStyle(fontName = "Arial", textDecoration = "bold")
modifyBaseFont(wb, fontName = "Arial", fontSize = 10)
add <- function(name, d) { addWorksheet(wb, name); writeData(wb, name, d, headerStyle = hs); setColWidths(wb, name, 1:ncol(d), "auto"); freezePane(wb, name, firstRow = TRUE) }
r2 <- function(d) { d <- copy(d); for (j in names(d)) if (is.numeric(d[[j]]) && !is.integer(d[[j]])) set(d, j = j, value = round(d[[j]], 4)); d }
add("README", rules)
add("Yearly", r2(Y))
add("Age_USD_M", r2(Aw)); add("Age_pct_of_CHD", r2(Ap)); add("Age_projects", An); add("Age_long", r2(A))
add("Trends", r2(Tr)); add("Top_ICs", r2(IC)); add("ICs_by_year_USD_M", r2(ICy)); add("Mechanism", r2(ACT))
add("Keyword_vs_RCDC", r2(O)); add("Validation_CHD", r2(V)); add("Validation_age", r2(VA)); add("Validation_list", Vlist)
add("CHD_projects", L)
saveWorkbook(wb, file.path(CONFIG$out_dir, "chd_nih_funding_2013_2026.xlsx"), overwrite = TRUE)
print(r2(Y[, .(FY, nih_USD_B, chd_projects, chd_USD_M, chd_pct_of_NIH, rcdc_USD_M, rcdc_pct_of_NIH)]))
print(r2(Ap)); print(r2(Tr)); print(head(r2(IC), 8)); print(r2(O[is.na(FY)])); print(AG); print(V); print(VA)
