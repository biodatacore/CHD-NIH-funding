#' 09_manual_check.R -- Excel workbook for manual checks of every major CHD categorization.
#' Mirrors the layout of the WHR validation workbook and
#' validation_total_WHR.xlsx (Instructions + Review sheets, Arial, freeze panes, filters,
#' 0/1 or Agree/Disagree dropdowns). Adds RePORTER hyperlinks (appl_id), pipeline labels,
#' the rule that fired, matched terms, prior 1-reviewer judgments, and Summary formulas.
#' Abstracts are scrubbed of likely investigator-name phrases. No journal names; metadata blanked.
source("R/00_setup.R"); source("R/terms.R")
suppressMessages({library(openxlsx); library(stringi)})
set.seed(CONFIG$seed)

# ---- helpers ------------------------------------------------------------------------------------
ILL <- "[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f]"
clean <- function(v, n = 32000L) {
  v <- as.character(v); v[is.na(v)] <- ""
  v <- stri_replace_all_regex(v, ILL, "")
  v <- stri_replace_all_regex(v, "_x00[0-1][0-9A-Fa-f]_", "")
  # scrub likely named investigators (keep science text; flag residual names in Instructions)
  v <- stri_replace_all_regex(v,
    "(?i)\\b(dr\\.?|prof(?:essor)?\\.?|mrs?\\.?|ms\\.)\\s+[A-Z][a-z]+(?:\\s+[A-Z]\\.?)*\\s+[A-Z][a-z]+(-[A-Z][a-z]+)?",
    "[NAME]")
  v <- stri_replace_all_regex(v,
    "(?i)\\b(candidate|principal investigator|pi|mentor|co-?investigator|trainee)\\s*[:：]\\s*[^\\n\\.]{0,80}",
    "\\1: [NAME]")
  v <- stri_replace_all_regex(v, "(?i)\\b[A-Z][a-z]+(?:\\s+[A-Z]\\.)?\\s+[A-Z][a-z]+,\\s*(MD|PhD|MD/PhD|DO|DVM|RN|NP)\\b", "[NAME], \\1")
  substr(v, 1, n)
}
fin <- function(wb) {
  p <- wb$core; if (!is.null(p)) { try(p$creator <- "", silent = TRUE); try(p$lastModifiedBy <- "", silent = TRUE)
    try(p$title <- "", silent = TRUE); try(p$subject <- "", silent = TRUE); try(p$description <- "", silent = TRUE) }
  wb
}
F  <- createStyle(fontName = "Arial", fontSize = 11, wrapText = TRUE, valign = "top")
FB <- createStyle(fontName = "Arial", fontSize = 11, textDecoration = "bold", wrapText = TRUE, valign = "top")
FL <- createStyle(fontName = "Arial", fontSize = 11, fontColour = "#0563C1", textDecoration = "underline")
ok_text <- function(v) !is.na(v) & nchar(trimws(v)) >= 40

# ---- APPLICATION_ID (parent row preferred) + abstract / PHR from WHR rows ----------------------
say("loading row text + appl_id …")
RT <- rbindlist(lapply(CONFIG$years, function(y) {
  r <- readRDS(file.path(CONFIG$whr_work, "rows", sprintf("rows_%d.rds", y)))
  r <- r[!is.na(FULL_PROJECT_NUM)]
  r[, par := is.na(SUBPROJECT_ID)]
  setorder(r, FULL_PROJECT_NUM, -par)
  r[, .SD[1], by = FULL_PROJECT_NUM][, .(FY = y, FULL_PROJECT_NUM, APPLICATION_ID,
    ABSTRACT_TEXT, PHR)]
}))
C <- readRDS(wp("C.rds"))
C <- merge(C, RT, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)
# CVD flag from WHR CV cache
Gcv <- readRDS(file.path(CONFIG$whr_work, "cv", "G.rds"))[, .(FY, FULL_PROJECT_NUM, cv)]
C <- merge(C, Gcv, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)
C[is.na(cv), cv := FALSE]

# ---- rule that fired + matched strong/weak terms -----------------------------------------------
rule_fired <- function(d) {
  fcase(
    d$t_str >= 1, "strong CHD term in title",
    d$s_str >= 3, ">=3 strong CHD mentions in text",
    d$s_str >= 2 & d$s_weak >= 2, "2 strong + >=2 weak mentions",
    d$s_str >= 1 & (d$t_pedcard | (d$t_ped & d$t_cardi)), ">=1 strong + pediatric-cardiac title",
    d$rcdc & !d$kw, "RCDC CHD only (no keyword match)",
    default = "no CHD rule (negative / near-miss)")
}
match_terms <- function(title, text) {
  tx <- paste(tolower(fifelse(is.na(title), "", title)),
              tolower(fifelse(is.na(text), "", text)))
  s <- unique(unlist(stri_extract_all_regex(tx, CHD_STRONG)))
  w <- unique(unlist(stri_extract_all_regex(tx, CHD_WEAK)))
  s <- s[!is.na(s)]; w <- w[!is.na(w)]
  paste0("strong: ", if (length(s)) paste(s, collapse = "; ") else "(none)",
         " | weak: ", if (length(w)) paste(w, collapse = "; ") else "(none)")
}

# ---- prior 1-reviewer judgments (from R/04_sample.R + review_judgments.R) ---------------------
S <- readRDS(wp("sample.rds"))
source("data/validation/review_judgments.R")
S[, k := as.integer(sub(".*_", "", id))]
S[, prior_CHD := "yes"]
for (s in names(chd_no)) S[set == s & k %in% chd_no[[s]], prior_CHD := "no"]
for (s in names(chd_partial)) S[set == s & k %in% chd_partial[[s]], prior_CHD := "partial"]
S[set == "S4_age", prior_age_ok := !k %in% age_wrong]
S[set == "S4_age", prior_CHD := NA_character_]
Prior <- S[, .(FY, FULL_PROJECT_NUM, prior_sample = set, prior_id = id,
               prior_CHD_judgment = prior_CHD, prior_age_correct = prior_age_ok)]

# ---- sampling pools ----------------------------------------------------------------------------
# Eligible: has abstract; prefer non-intramural for review readability (keep Z if CHD+)
elig <- function(d) d[ok_text(ABSTRACT_TEXT)]
# 1) All unique CORE projects that are keyword CHD at least once: most recent FY with text
Kw <- elig(C[kw == TRUE])
setorder(Kw, CORE_PROJECT_NUM, -FY)
Kw1 <- Kw[!duplicated(CORE_PROJECT_NUM)][, stratum := "Keyword CHD (all unique cores)"]
# 2) Keyword-only discordants (FY2016-2025), unique cores
Ko <- elig(C[kw & !rcdc & rcdc_avail])
setorder(Ko, CORE_PROJECT_NUM, -FY)
Ko1 <- Ko[!duplicated(CORE_PROJECT_NUM)][, stratum := "Keyword only (not RCDC)"]
# 3) RCDC-only discordants, unique cores, sample 100
Ro <- elig(C[rcdc & !kw])
setorder(Ro, CORE_PROJECT_NUM, -FY)
Ro1 <- Ro[!duplicated(CORE_PROJECT_NUM)]
set.seed(CONFIG$seed); Ro1 <- Ro1[sample.int(.N)][seq_len(min(100L, .N))][, stratum := "RCDC only (not keyword)"]
# 4) Near-miss negatives: 1-2 strong mentions, not kw, not rcdc; sample 50 unique cores
Nm <- elig(C[!kw & !rcdc & s_str %in% 1:2])
setorder(Nm, CORE_PROJECT_NUM, -FY)
Nm1 <- Nm[!duplicated(CORE_PROJECT_NUM)]
set.seed(CONFIG$seed + 1L); Nm1 <- Nm1[sample.int(.N)][seq_len(min(50L, .N))][, stratum := "Near-miss negative (1-2 strong terms)"]
# Combined CHD classification sheet (dedupe by CORE if a project appears in >1 stratum: keep first)
# Flag keyword-only cores inside the keyword-CHD universe; keep RCDC-only and near-miss as extra strata
Kw1[, discordance := fifelse(CORE_PROJECT_NUM %in% Ko1$CORE_PROJECT_NUM, "Keyword only (not RCDC)", "")]
CHD <- rbindlist(list(Kw1, Ro1, Nm1), fill = TRUE)
CHD[is.na(discordance), discordance := ""]
CHD[, keep := !duplicated(CORE_PROJECT_NUM)]
CHD <- CHD[keep == TRUE][, keep := NULL]
set.seed(CONFIG$seed + 2L); CHD <- CHD[sample.int(.N)]
CHD[, review_id := sprintf("CHD-%03d", .I)]

# Age sheet: all keyword unique cores (same Kw1 set), random order, stratified note
Age <- copy(Kw1)
set.seed(CONFIG$seed + 3L); Age <- Age[sample.int(.N)]
Age[, review_id := sprintf("AGE-%03d", .I)]

# CVD sheet: all keyword CHD cores + 40 CVD non-CHD + 40 non-CVD non-CHD
Cv_pos <- copy(Kw1)[, stratum := fifelse(cv, "Keyword CHD & CVD", "Keyword CHD, not CVD")]
set.seed(CONFIG$seed + 4L)
Cv_cv <- elig(C[!kw & cv == TRUE]); setorder(Cv_cv, CORE_PROJECT_NUM, -FY)
Cv_cv <- Cv_cv[!duplicated(CORE_PROJECT_NUM)][sample.int(.N)][seq_len(min(40L, .N))][, stratum := "CVD, not keyword CHD"]
Cv_no <- elig(C[!kw & cv == FALSE & s_str == 0]); setorder(Cv_no, CORE_PROJECT_NUM, -FY)
Cv_no <- Cv_no[!duplicated(CORE_PROJECT_NUM)][sample.int(.N)][seq_len(min(40L, .N))][, stratum := "Neither CVD nor keyword CHD"]
CVD <- rbindlist(list(Cv_pos, Cv_cv, Cv_no), fill = TRUE)
set.seed(CONFIG$seed + 5L); CVD <- CVD[sample.int(.N)]
CVD[, review_id := sprintf("CVD-%03d", .I)]

# Attach prior judgments + rule + matched terms + scrubbed text
enrich <- function(d) {
  d <- merge(d, Prior, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)
  d[, `:=`(rule = rule_fired(.SD),
           matched_terms = { m <- character(.N); for (i in seq_len(.N)) m[i] <- match_terms(title[i], ABSTRACT_TEXT[i]); m },
           title_c = clean(title, 500L),
           abstract_c = clean(ABSTRACT_TEXT, 8000L),
           phr_c = clean(PHR, 4000L),
           reporter_url = fifelse(!is.na(APPLICATION_ID) & APPLICATION_ID != "",
                                  paste0("https://reporter.nih.gov/project-details/", APPLICATION_ID), NA_character_))]
  d[, phr_c := fifelse(phr_c == "" | phr_c == "nan", "(no public health narrative in source record)", phr_c)]
  d
}
CHD <- enrich(CHD); Age <- enrich(Age); CVD <- enrich(CVD)
say(sprintf("sheets: CHD=%d Age=%d CVD=%d", nrow(CHD), nrow(Age), nrow(CVD)))

# ---- workbook ----------------------------------------------------------------------------------
wb <- createWorkbook()
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

add_instructions <- function() {
  addWorksheet(wb, "Instructions")
  lines <- list(
    c("Manual validation – NIH congenital heart disease (CHD) funding categorizations", ""),
    c("", ""),
    c("Purpose", "Check every major automated label used in the CHD funding brief: keyword CHD classification, age focus, CVD-denominator membership, and (as reference) the mortality ICD queries."),
    c("", ""),
    c("How to review", "On each Review sheet read the Title, Abstract and Public health narrative. Use only that text (plus the RePORTER link if you want the full record). Do not look up how the pipeline labelled the grant before you decide."),
    c("", "Enter Agree / Disagree / Unsure in the Judgment column (dropdown). If Disagree, choose a Corrected category from its dropdown. Use Comments for anything uncertain."),
    c("", "A grant can be reviewed on more than one sheet (CHD, Age, CVD); judge each sheet’s question independently."),
    c("", ""),
    c("Sheets", ""),
    c("CHD_classification", "Is CHD a primary/substantial focus? Rows = all unique core projects the keyword classifier called CHD, plus keyword-only and RCDC-only discordants and a near-miss negative sample. One representative fiscal year per core (most recent with an abstract)."),
    c("Age_focus", "Among keyword CHD projects, is the age-focus label correct? Categories: Pediatric, Adult, Both, Basic/non-age-specific, Unclear."),
    c("CVD_membership", "Is the grant cardiovascular under the women’s-CV funding definition (same as the CVD denominator)? Includes all keyword CHD cores plus samples of CVD/non-CVD non-CHD grants."),
    c("Mortality_ICD_definitions", "Reference only – CDC WONDER ICD-10 queries used for the mortality figures (not a grant review)."),
    c("Summary", "Agreement tallies and precision-style rates; formulas update when you fill Judgment columns."),
    c("Prior_judgments", "Earlier single-reviewer judgments on the seeded validation sample (for reference; not the answer key for every row)."),
    c("", ""),
    c("Column", "Meaning"),
    c("RePORTER", "Clickable link to the NIH RePORTER project-details page for this application ID (this project-year)."),
    c("Pipeline CHD / Age / CVD", "What the automated rules assigned."),
    c("Rule that fired", "Which keyword rule (or RCDC-only / near-miss) placed the grant in its stratum."),
    c("Matched terms", "Strong and weak CHD terms found in the title + abstract (for quick checking)."),
    c("Prior CHD judgment", "If this project-year was in the earlier seeded sample: yes / partial / no (or blank)."),
    c("Judgment", "Your Agree / Disagree / Unsure."),
    c("Corrected category", "If Disagree, pick the category you believe is correct."),
    c("Reviewer code / Comments", "A reviewer code on every row you review; free-text notes."),
    c("", ""),
    c("CHD definition (enter Agree if…)", "Primary or substantial focus on congenital heart disease or a named lesion/palliation (Fontan, HLHS, tetralogy, TGA, coarctation, septal defects, ACHD, etc.). Merely citing CHD as background motivation for basic heart-development work without CHD as an aim → Disagree (not CHD) or mark Corrected = partial."),
    c("Age categories", "Pediatric: children/fetuses/neonates as the study population. Adult: adults with CHD / ACHD. Both: both age groups or an explicit lifespan/transition focus. Basic/non-age-specific: mechanistic/animal/iPSC/developmental work without a human age focus. Unclear: none of the above."),
    c("CVD definition", "Same as the women’s CV funding analysis: CV is a substantive part of the parent award (CV term in title or repeated CV terms in abstract/PHR after removing non-CV usages)."),
    c("", ""),
    c("De-identification", "Investigator names and contact details are not included as fields. Abstracts were scrubbed of common ‘Dr./Prof./Name, MD/PhD’ and ‘Candidate:/PI:’ patterns and replaced with [NAME]. Scrubbing is imperfect – if a name remains, ignore it for judging and do not copy names into Comments."),
    c("Sampling notes", sprintf("Seed %s. Keyword CHD sheet: %d unique cores. RCDC-only sample n=%d. Near-miss sample n=%d. CVD non-CHD samples n=40+40. FY2026 is a partial fiscal year.",
                              CONFIG$seed, nrow(Kw1), nrow(Ro1), nrow(Nm1))),
    c("Mirrored layout", "Instructions + Review sheets, Arial 11, freeze panes, filters, wrap text, adjudication dropdowns – same pattern as validation_CV_WHR.xlsx and validation_total_WHR.xlsx in the women’s health funding validation folder.")
  )
  for (i in seq_along(lines)) {
    writeData(wb, "Instructions", lines[[i]][1], startCol = 1, startRow = i)
    writeData(wb, "Instructions", lines[[i]][2], startCol = 2, startRow = i)
  }
  setColWidths(wb, "Instructions", 1, 34); setColWidths(wb, "Instructions", 2, 110)
  addStyle(wb, "Instructions", F, rows = 1:length(lines), cols = 1:2, gridExpand = TRUE)
  addStyle(wb, "Instructions", FB, rows = 1, cols = 1)
}

style_review <- function(sheet, n, widths) {
  for (i in seq_along(widths)) setColWidths(wb, sheet, i, widths[i])
  addStyle(wb, sheet, FB, rows = 1, cols = seq_along(widths), gridExpand = TRUE)
  if (n >= 1) addStyle(wb, sheet, F, rows = 2:(n + 1), cols = seq_along(widths), gridExpand = TRUE)
  freezePane(wb, sheet, firstActiveRow = 2, firstActiveCol = 2)
  addFilter(wb, sheet, rows = 1, cols = seq_along(widths))
  setRowHeights(wb, sheet, rows = 1, heights = 30)
}

add_dv <- function(sheet, col, rows, values, title = "Choose from list") {
  if (rows < 2) return()
  dv <- dataValidation(sheet = sheet, cols = col, rows = 2:rows,
                       type = "list", value = paste(values, collapse = ","),
                       allowBlank = TRUE, showErrorMsg = TRUE, errorTitle = title,
                       errorStyle = "warning")
  # openxlsx 4.x API:
  invisible(NULL)
}

# openxlsx dataValidation helper compatible with both APIs
put_dropdown <- function(sheet, col_letter, last_row, choices) {
  if (last_row < 2) return()
  col <- match(col_letter, LETTERS)
  dataValidation(wb, sheet, cols = col, rows = 2:last_row, type = "list", value = paste(choices, collapse = ","),
                 allowBlank = TRUE, showErrorMsg = TRUE)
}

write_chd_sheet <- function() {
  sh <- "CHD_classification"; addWorksheet(wb, sh)
  d <- CHD[, .(
    `Review ID` = review_id, `Sampling stratum` = stratum, Discordance = discordance,
    `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY, IC, Activity = ACT,
    APPLICATION_ID = as.character(APPLICATION_ID), RePORTER = NA_character_, Title = title_c,
    `Abstract / project summary` = abstract_c, `Public health narrative` = phr_c,
    `Matched CHD terms` = matched_terms, `Rule that fired` = rule,
    `Pipeline keyword CHD` = as.integer(kw), `Pipeline RCDC CHD` = as.integer(rcdc),
    `Prior CHD judgment` = fifelse(is.na(prior_CHD_judgment), "", prior_CHD_judgment),
    Judgment = "", `Corrected category` = "", `Reviewer code` = "", Comments = "")]
  # openxlsx hyperlink class on the RePORTER column (display text = URL; Excel shows as link)
  d$RePORTER <- fifelse(is.na(CHD$reporter_url), "", CHD$reporter_url)
  class(d$RePORTER) <- "hyperlink"
  writeData(wb, sh, d)
  n <- nrow(d)
  style_review(sh, n, c(11, 28, 22, 20, 10, 6, 8, 14, 12, 40, 90, 50, 36, 28, 12, 12, 14, 12, 18, 12, 28))
  put_dropdown(sh, "R", n + 1, c("Agree", "Disagree", "Unsure"))
  put_dropdown(sh, "S", n + 1, c("CHD yes", "CHD partial", "CHD no"))
}

write_age_sheet <- function() {
  sh <- "Age_focus"; addWorksheet(wb, sh)
  sig <- Age[, sprintf("ped_title=%s pedcard=%s ped_n=%d | adult_title=%s adult_n=%d | lifespan_n=%d | basic_n=%d clinical_n=%d | basic_dom=%s",
                       t_ped, t_pedcard, s_ped, t_adu, s_adu, s_life, s_basic, s_hum, basic_dom)]
  d <- Age[, .(
    `Review ID` = review_id, `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY, IC,
    APPLICATION_ID = as.character(APPLICATION_ID), RePORTER = NA_character_, Title = title_c,
    `Abstract / project summary` = abstract_c, `Public health narrative` = phr_c,
    `Matched CHD terms` = matched_terms, `Pipeline age focus` = as.character(age),
    `Age rule signals` = sig,
    `Prior age correct` = fifelse(is.na(prior_age_correct), "", as.character(as.integer(prior_age_correct))),
    Judgment = "", `Corrected age focus` = "", `Reviewer code` = "", Comments = "")]
  d$RePORTER <- fifelse(is.na(Age$reporter_url), "", Age$reporter_url)
  class(d$RePORTER) <- "hyperlink"
  writeData(wb, sh, d)
  n <- nrow(d)
  style_review(sh, n, c(11, 20, 10, 6, 12, 14, 40, 90, 50, 36, 18, 40, 12, 12, 22, 12, 28))
  put_dropdown(sh, "N", n + 1, c("Agree", "Disagree", "Unsure"))
  put_dropdown(sh, "O", n + 1, c("Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear"))
}

write_cvd_sheet <- function() {
  sh <- "CVD_membership"; addWorksheet(wb, sh)
  d <- CVD[, .(
    `Review ID` = review_id, `Sampling stratum` = stratum, `Project number` = FULL_PROJECT_NUM,
    `Fiscal year` = FY, IC, APPLICATION_ID = as.character(APPLICATION_ID), RePORTER = NA_character_,
    Title = title_c, `Abstract / project summary` = abstract_c, `Public health narrative` = phr_c,
    `Pipeline CVD` = as.integer(cv), `Pipeline keyword CHD` = as.integer(kw),
    Judgment = "", `Corrected CVD` = "", `Reviewer code` = "", Comments = "")]
  d$RePORTER <- fifelse(is.na(CVD$reporter_url), "", CVD$reporter_url)
  class(d$RePORTER) <- "hyperlink"
  writeData(wb, sh, d)
  n <- nrow(d)
  style_review(sh, n, c(11, 28, 20, 10, 6, 12, 14, 40, 90, 50, 12, 12, 12, 14, 12, 28))
  put_dropdown(sh, "M", n + 1, c("Agree", "Disagree", "Unsure"))
  put_dropdown(sh, "N", n + 1, c("CVD yes", "CVD no"))
}

write_mortality <- function() {
  sh <- "Mortality_ICD_definitions"; addWorksheet(wb, sh)
  d <- data.table(
    Item = c("CHD, underlying cause", "CHD, any mention (multiple cause)", "All CVD (denominator base)",
             "Diseases of heart (denominator base)", "Denominators as used", "Pediatric ages", "Adult ages",
             "Files 2013-2017", "Files 2018-2024", "API", "Suppression", "Note"),
    Definition = c(
      "Underlying cause of death ICD-10 Q20-Q26 (congenital malformations of cardiac chambers, cardiac septa, pulmonary/tricuspid/aortic/mitral valves, other heart, great arteries, great veins).",
      "Multiple cause: ICD-10 Q20-Q26 mentioned anywhere on the death certificate (D77 / D157, O_mcd = V13).",
      "Underlying cause ICD-10 I00-I99 (Diseases of the circulatory system).",
      "Underlying cause 113-cause list GR113-054 = I00-I09, I11, I13, I20-I51.",
      "Because Q codes lie outside chapter I, denominators = (CVD or heart) PLUS underlying-cause CHD.",
      "Single-year ages 0-17 (V52 filter).",
      "All ages minus pediatric (includes age not stated).",
      "D76 Underlying Cause + D77 Multiple Cause, bridged-race final.",
      "D158 Underlying Cause + D157 Multiple Cause, single-race final (2024 is FINAL, not provisional).",
      "https://wonder.cdc.gov/controller/datarequest/{D76|D77|D157|D158}",
      "WONDER suppresses counts 1-9; no suppressed yearly cells were used.",
      "Reference sheet only – not a grant-level review. See METHODS.md and Fig7-8 footnotes for caveats."))
  writeData(wb, sh, d)
  setColWidths(wb, sh, 1, 36); setColWidths(wb, sh, 2, 120)
  addStyle(wb, sh, FB, rows = 1, cols = 1:2)
  addStyle(wb, sh, F, rows = 2:(nrow(d) + 1), cols = 1:2, gridExpand = TRUE)
}

write_prior <- function() {
  sh <- "Prior_judgments"; addWorksheet(wb, sh)
  P <- S[, .(prior_id = id, sample_set = set, FY, project_number = FULL_PROJECT_NUM, IC, title = clean(title, 300),
             pipeline_kw = kw, pipeline_rcdc = rcdc, pipeline_age = as.character(age),
             prior_CHD_judgment = prior_CHD, prior_age_correct = prior_age_ok)]
  writeData(wb, sh, P)
  setColWidths(wb, sh, 1:ncol(P), c(12, 14, 8, 20, 6, 50, 10, 10, 18, 14, 12))
  addStyle(wb, sh, FB, rows = 1, cols = 1:ncol(P))
  addStyle(wb, sh, F, rows = 2:(nrow(P) + 1), cols = 1:ncol(P), gridExpand = TRUE)
  freezePane(wb, sh, firstRow = TRUE)
  addFilter(wb, sh, rows = 1, cols = 1:ncol(P))
}

write_summary <- function() {
  sh <- "Summary"; addWorksheet(wb, sh)
  # CHD sheet: Judgment in column Q (17), Pipeline kw in N (14)
  # Build formula block
  rows <- list(
    c("Sheet", "Metric", "Formula / value", "Notes"),
    c("CHD_classification", "Rows", as.character(nrow(CHD)), "Unique cores; see Sampling stratum filter"),
    c("CHD_classification", "Judgments filled", '=COUNTA(CHD_classification!Q:Q)-1', "Non-blank Judgment cells"),
    c("CHD_classification", "Agree", '=COUNTIF(CHD_classification!R:R,"Agree")', ""),
    c("CHD_classification", "Disagree", '=COUNTIF(CHD_classification!R:R,"Disagree")', ""),
    c("CHD_classification", "Unsure", '=COUNTIF(CHD_classification!R:R,"Unsure")', ""),
    c("CHD_classification", "Agreement rate (excl. Unsure)", '=IF((B4+B5)=0,"",B4/(B4+B5))', "Agree / (Agree+Disagree)"),
    c("CHD_classification", "Keyword+ with prior yes or partial (seeded)", as.character(sum(S$set == "S1_kw" & S$prior_CHD %in% c("yes", "partial"), na.rm = TRUE)), "From Prior_judgments S1_kw"),
    c("CHD_classification", "Keyword+ seeded n", as.character(sum(S$set == "S1_kw")), ""),
    c("Age_focus", "Rows", as.character(nrow(Age)), ""),
    c("Age_focus", "Agree", '=COUNTIF(Age_focus!N:N,"Agree")', ""),
    c("Age_focus", "Disagree", '=COUNTIF(Age_focus!N:N,"Disagree")', ""),
    c("Age_focus", "Unsure", '=COUNTIF(Age_focus!N:N,"Unsure")', ""),
    c("Age_focus", "Agreement rate (excl. Unsure)", '=IF((B11+B12)=0,"",B11/(B11+B12))', ""),
    c("Age_focus", "Prior age correct (seeded S4)", as.character(sum(S$set == "S4_age" & S$prior_age_ok == TRUE, na.rm = TRUE)), ""),
    c("Age_focus", "Prior age seeded n", as.character(sum(S$set == "S4_age")), ""),
    c("CVD_membership", "Rows", as.character(nrow(CVD)), ""),
    c("CVD_membership", "Agree", '=COUNTIF(CVD_membership!M:M,"Agree")', ""),
    c("CVD_membership", "Disagree", '=COUNTIF(CVD_membership!M:M,"Disagree")', ""),
    c("CVD_membership", "Unsure", '=COUNTIF(CVD_membership!M:M,"Unsure")', ""),
    c("CVD_membership", "Agreement rate (excl. Unsure)", '=IF((B18+B19)=0,"",B18/(B18+B19))', ""),
    c("", "", "", ""),
    c("Stratum counts (CHD_classification)", "", "", ""),
    c("Keyword CHD (all unique cores)", as.character(sum(CHD$stratum == "Keyword CHD (all unique cores)")), "", ""),
    c("Keyword only (not RCDC)", as.character(sum(CHD$stratum == "Keyword only (not RCDC)")), "", ""),
    c("RCDC only (not keyword)", as.character(sum(CHD$stratum == "RCDC only (not keyword)")), "", ""),
    c("Near-miss negative", as.character(sum(CHD$stratum == "Near-miss negative (1-2 strong terms)")), "", ""),
    c("", "", "", ""),
    c("IC note", "Administering IC is taken from the parent project record (same as the analysis). Spot-check via RePORTER if needed; no separate IC adjudication column.", "", "")
  )
  for (i in seq_along(rows)) {
    for (j in 1:4) writeData(wb, sh, rows[[i]][j], startCol = j, startRow = i)
  }
  # Write live formulas where the third column starts with =
  for (i in seq_along(rows)) {
    if (startsWith(rows[[i]][3], "=")) writeFormula(wb, sh, startRow = i, startCol = 2, x = rows[[i]][3])
  }
  # Fix: I put formulas in column C in the list but wrote agreement refs to B – rewrite Summary more carefully
  setColWidths(wb, sh, 1:4, c(42, 18, 55, 40))
  addStyle(wb, sh, FB, rows = 1, cols = 1:4)
  addStyle(wb, sh, F, rows = 2:length(rows), cols = 1:4, gridExpand = TRUE)
}

# Rebuild Summary with correct formula columns
write_summary2 <- function() {
  sh <- "Summary"
  # Clear and rewrite
  if ("Summary" %in% names(wb)) removeWorksheet(wb, sh); addWorksheet(wb, sh)
  writeData(wb, sh, data.frame(
    Sheet = c("CHD_classification", "CHD_classification", "CHD_classification", "CHD_classification", "CHD_classification",
              "Age_focus", "Age_focus", "Age_focus", "Age_focus",
              "CVD_membership", "CVD_membership", "CVD_membership", "CVD_membership",
              "CHD_classification", "CHD_classification", "CHD_classification", "CHD_classification",
              "Prior (seeded)", "Prior (seeded)", "Prior (seeded)", "Prior (seeded)"),
    Metric = c("Rows", "Agree", "Disagree", "Unsure", "Agreement rate (excl. Unsure)",
               "Rows", "Agree", "Disagree", "Agreement rate (excl. Unsure)",
               "Rows", "Agree", "Disagree", "Agreement rate (excl. Unsure)",
               "Stratum: Keyword CHD cores", "Stratum: Keyword only", "Stratum: RCDC only", "Stratum: Near-miss",
               "S1 keyword+ CHD yes or partial", "S1 keyword+ n", "S4 age correct", "S4 age n"),
    Value = NA_real_,
    Notes = c(as.character(nrow(CHD)), "Judgment col Q", "Judgment col Q", "Judgment col Q", "Agree/(Agree+Disagree)",
              as.character(nrow(Age)), "Judgment col N", "Judgment col N", "Agree/(Agree+Disagree)",
              as.character(nrow(CVD)), "Judgment col M", "Judgment col M", "Agree/(Agree+Disagree)",
              as.character(sum(CHD$stratum == "Keyword CHD (all unique cores)")),
              as.character(sum(CHD$discordance == "Keyword only (not RCDC)", na.rm = TRUE)),
              as.character(sum(CHD$stratum == "RCDC only (not keyword)")),
              as.character(sum(CHD$stratum == "Near-miss negative (1-2 strong terms)")),
              as.character(sum(S$set == "S1_kw" & S$prior_CHD %in% c("yes", "partial"), na.rm = TRUE)),
              as.character(sum(S$set == "S1_kw")),
              as.character(sum(S$set == "S4_age" & S$prior_age_ok == TRUE, na.rm = TRUE)),
              as.character(sum(S$set == "S4_age"))),
    stringsAsFactors = FALSE)
  )
  # Formulas in Value column for Agree/Disagree/Unsure/rates
  writeFormula(wb, sh, startRow = 2, startCol = 3, x = as.character(nrow(CHD)))
  writeFormula(wb, sh, startRow = 3, startCol = 3, x = 'COUNTIF(CHD_classification!R:R,"Agree")')
  writeFormula(wb, sh, startRow = 4, startCol = 3, x = 'COUNTIF(CHD_classification!R:R,"Disagree")')
  writeFormula(wb, sh, startRow = 5, startCol = 3, x = 'COUNTIF(CHD_classification!R:R,"Unsure")')
  writeFormula(wb, sh, startRow = 6, startCol = 3, x = 'IF((C3+C4)=0,"",C3/(C3+C4))')
  writeFormula(wb, sh, startRow = 7, startCol = 3, x = as.character(nrow(Age)))
  writeFormula(wb, sh, startRow = 8, startCol = 3, x = 'COUNTIF(Age_focus!N:N,"Agree")')
  writeFormula(wb, sh, startRow = 9, startCol = 3, x = 'COUNTIF(Age_focus!N:N,"Disagree")')
  writeFormula(wb, sh, startRow = 10, startCol = 3, x = 'IF((C8+C9)=0,"",C8/(C8+C9))')
  writeFormula(wb, sh, startRow = 11, startCol = 3, x = as.character(nrow(CVD)))
  writeFormula(wb, sh, startRow = 12, startCol = 3, x = 'COUNTIF(CVD_membership!M:M,"Agree")')
  writeFormula(wb, sh, startRow = 13, startCol = 3, x = 'COUNTIF(CVD_membership!M:M,"Disagree")')
  writeFormula(wb, sh, startRow = 14, startCol = 3, x = 'IF((C12+C13)=0,"",C12/(C12+C13))')
  setColWidths(wb, sh, 1:4, c(28, 40, 18, 55))
  addStyle(wb, sh, FB, rows = 1, cols = 1:4)
  addStyle(wb, sh, F, rows = 2:22, cols = 1:4, gridExpand = TRUE)
}

add_instructions()
write_chd_sheet()
write_age_sheet()
write_cvd_sheet()
write_mortality()
write_prior()
write_summary2()

# Blank identifying metadata
try({
  wb$core$creator <- "CHD funding validation"
  wb$core$lastModifiedBy <- ""
  wb$core$title <- "CHD funding manual validation"
  wb$core$subject <- ""
  wb$core$description <- ""
}, silent = TRUE)

out <- file.path(CONFIG$out_dir, "chd_manual_check.xlsx")
saveWorkbook(wb, out, overwrite = TRUE)
say("wrote ", out)
# spot-check a few RePORTER links
u <- na.omit(CHD$reporter_url)[1:5]
for (x in u) {
  code <- tryCatch({
    h <- curl::new_handle(); curl::handle_setopt(h, nobody = TRUE, timeout = 30)
    curl::curl_fetch_memory(x, handle = h)$status_code
  }, error = function(e) NA_integer_)
  say("RePORTER ", x, " -> HTTP ", code)
}
print(CHD[, .N, by = stratum])
print(CVD[, .N, by = stratum])
