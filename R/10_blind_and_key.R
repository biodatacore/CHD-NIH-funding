#' 10_blind_and_key.R -- Blind reviewer workbook + separate answer key from the manual-check data.
#' Blind file reveals nothing about pipeline labels; answer key holds them for scoring.
source("R/00_setup.R"); source("R/terms.R")
suppressMessages({library(openxlsx); library(stringi)})
set.seed(CONFIG$seed + 100L)

ILL <- "[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f]"
clean <- function(v, n = 32000L) {
  v <- as.character(v); v[is.na(v)] <- ""
  v <- stri_replace_all_regex(v, ILL, "")
  v <- stri_replace_all_regex(v, "_x00[0-1][0-9A-Fa-f]_", "")
  v <- stri_replace_all_regex(v, "(?i)\\b(dr\\.?|prof(?:essor)?\\.?|mrs?\\.?|ms\\.)\\s+[A-Z][a-z]+(?:\\s+[A-Z]\\.?)*\\s+[A-Z][a-z]+(-[A-Z][a-z]+)?", "[NAME]")
  v <- stri_replace_all_regex(v, "(?i)\\b(candidate|principal investigator|pi|mentor|co-?investigator|trainee)\\s*[:：]\\s*[^\\n\\.]{0,80}", "\\1: [NAME]")
  v <- stri_replace_all_regex(v, "(?i)\\b[A-Z][a-z]+(?:\\s+[A-Z]\\.)?\\s+[A-Z][a-z]+,\\s*(MD|PhD|MD/PhD|DO|DVM|RN|NP)\\b", "[NAME], \\1")
  v <- stri_replace_all_regex(v, "(?i)\\b(JAMA|Circulation|NEJM|N Engl J Med|Lancet|Nature|Science|BMJ)\\b[^\\.\\n]{0,40}", "[JOURNAL]")
  substr(v, 1, n)
}
F  <- createStyle(fontName = "Arial", fontSize = 11, wrapText = TRUE, valign = "top")
FB <- createStyle(fontName = "Arial", fontSize = 11, textDecoration = "bold", wrapText = TRUE, valign = "top")
FUNL <- createStyle(fontName = "Arial", fontSize = 11, wrapText = TRUE, valign = "top", locked = FALSE)
FLK  <- createStyle(fontName = "Arial", fontSize = 11, wrapText = TRUE, valign = "top", locked = TRUE)
FBK  <- createStyle(fontName = "Arial", fontSize = 11, textDecoration = "bold", wrapText = TRUE, valign = "top", locked = TRUE)

say("loading …")
RT <- rbindlist(lapply(CONFIG$years, function(y) {
  r <- readRDS(file.path(CONFIG$whr_work, "rows", sprintf("rows_%d.rds", y)))
  r <- r[!is.na(FULL_PROJECT_NUM)][, par := is.na(SUBPROJECT_ID)]
  setorder(r, FULL_PROJECT_NUM, -par)
  r[, .SD[1], by = FULL_PROJECT_NUM][, .(FY = y, FULL_PROJECT_NUM, APPLICATION_ID, ABSTRACT_TEXT, PHR)]
}))
C <- readRDS(wp("C.rds"))
C <- merge(C, RT, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)
Gcv <- readRDS(file.path(CONFIG$whr_work, "cv", "G.rds"))[, .(FY, FULL_PROJECT_NUM, cv)]
C <- merge(C, Gcv, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)
C[is.na(cv), cv := FALSE]
ok_text <- function(v) !is.na(v) & nchar(trimws(v)) >= 40
elig <- function(d) d[ok_text(ABSTRACT_TEXT)]

rule_fired <- function(d) fcase(
  d$t_str >= 1, "strong CHD term in title",
  d$s_str >= 3, ">=3 strong CHD mentions in text",
  d$s_str >= 2 & d$s_weak >= 2, "2 strong + >=2 weak mentions",
  d$s_str >= 1 & (d$t_pedcard | (d$t_ped & d$t_cardi)), ">=1 strong + pediatric-cardiac title",
  d$rcdc & !d$kw, "RCDC CHD only (no keyword match)",
  default = "no CHD rule (negative / near-miss)")
match_terms <- function(title, text) {
  tx <- paste(tolower(fifelse(is.na(title), "", title)), tolower(fifelse(is.na(text), "", text)))
  s <- unique(unlist(stri_extract_all_regex(tx, CHD_STRONG))); s <- s[!is.na(s)]
  w <- unique(unlist(stri_extract_all_regex(tx, CHD_WEAK))); w <- w[!is.na(w)]
  paste0("strong: ", if (length(s)) paste(s, collapse = "; ") else "(none)",
         " | weak: ", if (length(w)) paste(w, collapse = "; ") else "(none)")
}

# ---- pools (same logic as 09) -----------------------------------------------------------------
Kw <- elig(C[kw == TRUE]); setorder(Kw, CORE_PROJECT_NUM, -FY)
Kw1 <- Kw[!duplicated(CORE_PROJECT_NUM)][, `:=`(stratum = "Keyword CHD (all unique cores)", discordance = "")]
Ko <- elig(C[kw & !rcdc & rcdc_avail]); setorder(Ko, CORE_PROJECT_NUM, -FY)
Ko1 <- Ko[!duplicated(CORE_PROJECT_NUM)]
Kw1[CORE_PROJECT_NUM %in% Ko1$CORE_PROJECT_NUM, discordance := "Keyword only (not RCDC)"]
Ro <- elig(C[rcdc & !kw]); setorder(Ro, CORE_PROJECT_NUM, -FY)
Ro1 <- Ro[!duplicated(CORE_PROJECT_NUM)]
set.seed(CONFIG$seed); Ro1 <- Ro1[sample.int(.N)][seq_len(min(100L, .N))][, `:=`(stratum = "RCDC only (not keyword)", discordance = "")]
Nm <- elig(C[!kw & !rcdc & s_str %in% 1:2]); setorder(Nm, CORE_PROJECT_NUM, -FY)
Nm1 <- Nm[!duplicated(CORE_PROJECT_NUM)]
set.seed(CONFIG$seed + 1L); Nm1 <- Nm1[sample.int(.N)][seq_len(min(50L, .N))][, `:=`(stratum = "Near-miss negative (1-2 strong terms)", discordance = "")]
CHD <- rbindlist(list(Kw1, Ro1, Nm1), fill = TRUE)
CHD <- CHD[!duplicated(CORE_PROJECT_NUM)]
CHD[, `:=`(rule = rule_fired(.SD),
           matched_terms = { m <- character(.N); for (i in seq_len(.N)) m[i] <- match_terms(title[i], ABSTRACT_TEXT[i]); m },
           title_c = clean(title, 500L), abstract_c = clean(ABSTRACT_TEXT, 8000L),
           phr_c = clean(PHR, 4000L),
           reporter_url = fifelse(!is.na(APPLICATION_ID) & APPLICATION_ID != "",
                                  paste0("https://reporter.nih.gov/project-details/", APPLICATION_ID), NA_character_))]
CHD[, phr_c := fifelse(phr_c == "" | phr_c == "nan", "(no public health narrative in source record)", phr_c)]

# CVD samples
set.seed(CONFIG$seed + 4L)
Cv_cv <- elig(C[!kw & cv == TRUE]); setorder(Cv_cv, CORE_PROJECT_NUM, -FY)
Cv_cv <- Cv_cv[!duplicated(CORE_PROJECT_NUM)][sample.int(.N)][seq_len(min(40L, .N))][, stratum := "CVD, not keyword CHD"]
Cv_no <- elig(C[!kw & cv == FALSE & s_str == 0]); setorder(Cv_no, CORE_PROJECT_NUM, -FY)
Cv_no <- Cv_no[!duplicated(CORE_PROJECT_NUM)][sample.int(.N)][seq_len(min(40L, .N))][, stratum := "Neither CVD nor keyword CHD"]
Cv_pos <- copy(Kw1)[, stratum := fifelse(cv, "Keyword CHD & CVD", "Keyword CHD, not CVD")]
CVD <- rbindlist(list(Cv_pos, Cv_cv, Cv_no), fill = TRUE)
CVD[, `:=`(title_c = clean(title, 500L), abstract_c = clean(ABSTRACT_TEXT, 8000L), phr_c = clean(PHR, 4000L),
           reporter_url = fifelse(!is.na(APPLICATION_ID) & APPLICATION_ID != "",
                                  paste0("https://reporter.nih.gov/project-details/", APPLICATION_ID), NA_character_))]
CVD[, phr_c := fifelse(phr_c == "" | phr_c == "nan", "(no public health narrative in source record)", phr_c)]
CVD[, rule := rule_fired(.SD)]
CVD[, matched_terms := { m <- character(.N); for (i in seq_len(.N)) m[i] <- match_terms(title[i], ABSTRACT_TEXT[i]); m }]

# Prior judgments
S <- readRDS(wp("sample.rds")); source("data/validation/review_judgments.R")
S[, k := as.integer(sub(".*_", "", id))]
S[, prior_CHD := "yes"]
for (s in names(chd_no)) S[set == s & k %in% chd_no[[s]], prior_CHD := "no"]
for (s in names(chd_partial)) S[set == s & k %in% chd_partial[[s]], prior_CHD := "partial"]
S[set == "S4_age", prior_age_ok := !k %in% age_wrong]
S[set == "S4_age", prior_CHD := NA_character_]
Prior <- S[, .(FY, FULL_PROJECT_NUM, prior_sample = set, prior_id = id,
               prior_CHD_judgment = prior_CHD, prior_age_correct = prior_age_ok)]
CHD <- merge(CHD, Prior, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)
CVD <- merge(CVD, Prior, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)


# Map pipeline age factor -> blind age-population choices
gold_age_pop <- function(age) fcase(
  as.character(age) == "Pediatric", "Pediatric",
  as.character(age) == "Adult", "Adult",
  as.character(age) == "Both", "Both",
  as.character(age) == "Basic/non-age-specific", "Neither / not age-specific",
  as.character(age) == "Unclear", "Unclear",
  default = "Unclear")
CHD[, Gold_age_pop := gold_age_pop(age)]
CVD[, Gold_age_pop := gold_age_pop(age)]
CVD[, Gold_age_pop_note := "Derived from same age rules as CHD analysis; applicable to all CVD-sheet rows"]

# Shuffle and assign blind IDs
set.seed(CONFIG$seed + 100L); CHD <- CHD[sample.int(.N)][, blind_id := sprintf("B-CHD-%03d", .I)]
set.seed(CONFIG$seed + 101L); CVD <- CVD[sample.int(.N)][, blind_id := sprintf("B-CVD-%03d", .I)]
# Age = same CHD candidate universe (no leak of which are keyword+), independent shuffle + IDs
Age <- copy(CHD)
set.seed(CONFIG$seed + 102L); Age <- Age[sample.int(.N)][, blind_id := sprintf("B-AGE-%03d", .I)]

put_dd <- function(wb, sheet, col, last_row, choices) {
  if (last_row < 2) return()
  dataValidation(wb, sheet, cols = col, rows = 2:last_row, type = "list",
                 value = paste(choices, collapse = ","), allowBlank = TRUE, showErrorMsg = TRUE)
}
style_hdr <- function(wb, sheet, nc, widths, n, unlock_cols) {
  for (i in seq_along(widths)) setColWidths(wb, sheet, i, widths[i])
  addStyle(wb, sheet, FBK, rows = 1, cols = 1:nc, gridExpand = TRUE)
  if (n >= 1) {
    addStyle(wb, sheet, FLK, rows = 2:(n + 1), cols = 1:nc, gridExpand = TRUE)
    for (uc in unlock_cols) addStyle(wb, sheet, FUNL, rows = 2:(n + 1), cols = uc, gridExpand = TRUE)
  }
  freezePane(wb, sheet, firstActiveRow = 2, firstActiveCol = 2)
  addFilter(wb, sheet, rows = 1, cols = 1:nc)
  setRowHeights(wb, sheet, 1, 32)
  # Protect: no password (reviewers can unprotect if needed; noted in key)
  protectWorksheet(wb, sheet, protect = TRUE, lockSelectingLockedCells = FALSE,
                   lockSelectingUnlockedCells = FALSE, lockAutoFilter = FALSE, lockSorting = FALSE,
                   lockFormattingCells = FALSE)
}

# ========================= BLIND WORKBOOK =======================================================
wb <- createWorkbook()
addWorksheet(wb, "READ ME FIRST")
readme <- c(
  "BLIND MANUAL REVIEW — NIH congenital heart disease (CHD) funding categorizations",
  "",
  "PURPOSE",
  "1. You are checking three labels that an automated system assigned to NIH grant records: (A) whether the grant is about congenital heart disease, (B) if so, its age focus, and (C) whether cardiovascular disease is a substantial focus. Your judgments will be compared later to the system; you must NOT see or look up those system labels while reviewing.",
  "",
  "RULES — READ BEFORE YOU START",
  "2. Work alone. Do not discuss these grants with other reviewers or anyone who may have the answer key.",
  "3. Do NOT open or request the answer-key file. Do NOT try to infer how grants were sampled or labelled from Review IDs, order, or RePORTER metadata beyond the science in the text.",
  "4. Judge ONLY from the Title, Abstract / project summary, and Public health narrative on the sheet. You may click the RePORTER link for that row to read the same public abstract on NIH RePORTER if the cell text is truncated or hard to read — but do not use RePORTER to look up spending categories, study sections, or other labels that could reveal the system’s classification.",
  "5. Ignore any residual person names or “[NAME]” placeholders in the text. Do not copy names into Comments.",
  "6. Enter your answer in the dropdown columns only. Add your initials and the review date (YYYY-MM-DD) on every row you complete. Use Comments for anything uncertain.",
  "7. Expected effort: about 1–3 minutes per grant. You do not need to finish every sheet in one sitting; save often.",
  "8. When finished: save this file under the same name (or append your initials, e.g. chd_manual_check_BLIND_JD.xlsx) and return it by the path or email you were given. Do not paste answers into chat or email bodies.",
  "",
  "SHEETS",
  "9. CHD_review — For every grant: (a) Is congenital heart disease a primary or substantial focus? (b) Age population: Pediatric / Adult / Both / Neither-not age-specific / Unclear.",
  "10. Age_review — Same grant universe as CHD_review (independently shuffled). Choose the best age-focus category. If you believe the grant is not about CHD at all, choose “Not CHD”.",
  "11. CVD_review — (a) Is cardiovascular research a substantial focus? (b) Same age-population column as on CHD_review.",
  "",
  "DEFINITIONS — CHD (sheet CHD_review)",
  "12. Yes — Congenital heart disease (or a named congenital cardiac lesion / palliation) is a primary or substantial focus. Examples: Fontan physiology, hypoplastic left heart syndrome (HLHS), tetralogy of Fallot, transposition, coarctation, AVSD/VSD as congenital lesions, adult congenital heart disease (ACHD), Pediatric Heart Network CHD trials, devices specifically for congenital lesions.",
  "13. Partly — CHD is one aim or a clear motivation, but not the primary focus (e.g., basic heart-development biology that repeatedly cites CHD as the clinical rationale without studying a CHD population or lesion; a pediatric heart-disease network that mixes CHD with acquired disease).",
  "14. No — Not CHD-focused. Examples: coronary heart disease / atherosclerosis only; acquired cardiomyopathy or channelopathy without congenital lesions; general pediatric care; bicuspid aortic valve or patent ductus as an isolated adult/neonatal topic with no broader CHD framing; grants that only mention “congenital” in a non-cardiac birth-defect list.",
  "15. Unsure — Text too thin or ambiguous to decide. Prefer Unsure over guessing.",
  "",
  "DEFINITIONS — Age focus (sheet Age_review)",
  "16. Pediatric — Study population is fetuses, neonates, infants, children, or adolescents; or the work is explicitly pediatric cardiology / fetal cardiac.",
  "17. Adult — Study population is adults with CHD / ACHD / grown-up congenital heart disease, without a concurrent pediatric focus.",
  "18. Both — Explicitly spans children and adults, transition of care, or lifespan of CHD survivors.",
  "19. Basic/non-age-specific — Mechanistic, animal, embryo, iPSC, or developmental biology without a human age-group focus (even if the abstract cites “1% of live births”).",
  "20. Unclear — Human clinical/device/genetics work with no stated age group.",
  "21. Not CHD — Use when you would answer No on CHD_review for this grant.",
  "",
  "DEFINITIONS — CVD (sheet CVD_review)",
  "22. Yes — Cardiovascular disease or physiology is a substantial focus: heart, blood vessels, hypertension, stroke, cardiomyopathy, arrhythmia, CV surgery/devices, or major CV outcomes — regardless of sex or age. Congenital cardiac work counts as Yes.",
  "23. No — Not substantially cardiovascular (e.g., pure infectious disease, cancer without a cardiac aim, general neonatology).",
  "24. Unsure — Too ambiguous.",
  "",
  "AGE POPULATION COLUMN (on CHD_review and CVD_review — answer for every row)",
  "31. Pediatric — Study population is fetuses, neonates, infants, children, or adolescents (fetal/neonatal cardiac work = Pediatric).",
  "32. Adult — Adults with the condition (including ACHD / grown-up congenital heart disease) without a concurrent pediatric focus.",
  "33. Both — Explicitly spans children and adults, transition of care, lifespan CHD survivors, or networks such as the Pediatric Heart Network that enroll across ages.",
  "34. Neither / not age-specific — Basic science, animal, embryo, iPSC, or developmental work with no human age-group focus (even if it cites birth prevalence).",
  "35. Unclear — Human clinical/device/genetics work with no stated age group.",
  "36. Age_review is a separate sheet with the same CHD-candidate universe and a fuller age taxonomy (including Not CHD). Complete it as well; the population column on CHD_review/CVD_review is a short classification on those sheets.",
  "",
  "EDGE CASES",
  "25. “CHD” meaning coronary heart disease → No for CHD_review (unless congenital disease is also clearly present).",
  "26. Isolated bicuspid aortic valve, mitral prolapse, or PDA in preterms without broader congenital-heart framing → usually No or Partly; use judgment and Comments.",
  "27. Fontan / single ventricle / HLHS / tetralogy → almost always Yes for CHD.",
  "28. If Title and Abstract conflict, weight the Abstract’s stated aims.",
  "",
  "DROPDOWNS AND SAVING",
  "29. Only the yellow-unlocked answer columns, initials, date, and comments are editable (sheet protection is on; there is no password — do not unprotect to change other columns).",
  "30. Save frequently. Return the completed file; leave unanswered rows blank rather than guessing."
)
for (i in seq_along(readme)) writeData(wb, "READ ME FIRST", readme[i], startRow = i, startCol = 1)
setColWidths(wb, "READ ME FIRST", 1, 140)
addStyle(wb, "READ ME FIRST", FBK, rows = 1, cols = 1)
addStyle(wb, "READ ME FIRST", FLK, rows = 2:length(readme), cols = 1, gridExpand = TRUE)
protectWorksheet(wb, "READ ME FIRST", protect = TRUE)

# --- CHD_review (blind) ---
addWorksheet(wb, "CHD_review")
d <- CHD[, .(
  `Review ID` = blind_id, `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY, IC, Activity = ACT,
  APPLICATION_ID = as.character(APPLICATION_ID), RePORTER = fifelse(is.na(reporter_url), "", reporter_url),
  Title = title_c, `Abstract / project summary` = abstract_c, `Public health narrative` = phr_c,
  `CHD focus (Yes / Partly / No / Unsure)` = "",
  `Age population (Pediatric / Adult / Both / Neither / Unclear)` = "",
  `Reviewer code` = "", `Review date (YYYY-MM-DD)` = "", Comments = "")]
class(d$RePORTER) <- "hyperlink"
writeData(wb, "CHD_review", d)
n <- nrow(d)
style_hdr(wb, "CHD_review", ncol(d), c(12, 20, 10, 6, 8, 12, 14, 40, 90, 50, 18, 22, 12, 14, 28), n, unlock_cols = 11:15)
put_dd(wb, "CHD_review", 11, n + 1, c("Yes", "Partly", "No", "Unsure"))
put_dd(wb, "CHD_review", 12, n + 1, c("Pediatric", "Adult", "Both", "Neither / not age-specific", "Unclear"))

# --- Age_review (same candidates, reshuffled) ---
addWorksheet(wb, "Age_review")
dA <- Age[, .(
  `Review ID` = blind_id, `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY, IC,
  APPLICATION_ID = as.character(APPLICATION_ID), RePORTER = fifelse(is.na(reporter_url), "", reporter_url),
  Title = title_c, `Abstract / project summary` = abstract_c, `Public health narrative` = phr_c,
  `Age focus` = "", `Reviewer code` = "", `Review date (YYYY-MM-DD)` = "", Comments = "")]
class(dA$RePORTER) <- "hyperlink"
writeData(wb, "Age_review", dA)
nA <- nrow(dA)
style_hdr(wb, "Age_review", ncol(dA), c(12, 20, 10, 6, 12, 14, 40, 90, 50, 22, 12, 14, 28), nA, unlock_cols = 10:13)
put_dd(wb, "Age_review", 10, nA + 1, c("Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear", "Not CHD"))

# --- CVD_review ---
addWorksheet(wb, "CVD_review")
dC <- CVD[, .(
  `Review ID` = blind_id, `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY, IC,
  APPLICATION_ID = as.character(APPLICATION_ID), RePORTER = fifelse(is.na(reporter_url), "", reporter_url),
  Title = title_c, `Abstract / project summary` = abstract_c, `Public health narrative` = phr_c,
  `CVD substantial focus (Yes / No / Unsure)` = "",
  `Age population (Pediatric / Adult / Both / Neither / Unclear)` = "",
  `Reviewer code` = "", `Review date (YYYY-MM-DD)` = "", Comments = "")]
class(dC$RePORTER) <- "hyperlink"
writeData(wb, "CVD_review", dC)
nC <- nrow(dC)
style_hdr(wb, "CVD_review", ncol(dC), c(12, 20, 10, 6, 12, 14, 40, 90, 50, 18, 22, 12, 14, 28), nC, unlock_cols = 10:14)
put_dd(wb, "CVD_review", 10, nC + 1, c("Yes", "No", "Unsure"))
put_dd(wb, "CVD_review", 11, nC + 1, c("Pediatric", "Adult", "Both", "Neither / not age-specific", "Unclear"))

blind_path <- file.path(CONFIG$out_dir, "chd_manual_check_BLIND.xlsx")
try({ wb$core$creator <- ""; wb$core$lastModifiedBy <- ""; wb$core$title <- "CHD blind manual review"; wb$core$subject <- ""; wb$core$description <- "" }, silent = TRUE)
saveWorkbook(wb, blind_path, overwrite = TRUE)
say("blind -> ", blind_path)

# ========================= ANSWER KEY ===========================================================
ak <- createWorkbook()
addWorksheet(ak, "Notes")
notes <- c(
  "ANSWER KEY — do not give to reviewers.",
  "Blind file: outputs/chd_manual_check_BLIND.xlsx. Sheet protection has NO password (reviewers were told not to unprotect).",
  paste0("Seeds: CONFIG$seed=", CONFIG$seed, "; blind shuffles use seed+100 (CHD), +101 (CVD), +102 (Age)."),
  "Scoring: paste reviewer answers into Scoring by Review ID: CHD focus (col B), CHD age-pop (col F), Age_review (Age block col B), CVD focus (CVD block col B), CVD age-pop (CVD block col F).",
  "Gold CHD: Keyword CHD stratum -> Yes; RCDC only -> typically No or Partly (not keyword+); Near-miss -> No. Pipeline_keyword_CHD=1 is the primary Yes definition.",
  "Gold age: Pipeline_age among keyword CHD; for non-keyword strata Prefer Not CHD when scoring age only if reviewer says Not CHD — see Scoring notes.",
  "Gold CVD: Pipeline_CVD (broad2 / women’s-CV definition)."
)
for (i in seq_along(notes)) writeData(ak, "Notes", notes[i], startRow = i)
setColWidths(ak, "Notes", 1, 140); addStyle(ak, "Notes", FB, rows = 1, cols = 1)

addWorksheet(ak, "Key_CHD")
writeData(ak, "Key_CHD", CHD[, .(
  `Review ID` = blind_id, `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY, IC, Activity = ACT,
  APPLICATION_ID = as.character(APPLICATION_ID), Stratum = stratum, Discordance = discordance,
  Pipeline_keyword_CHD = as.integer(kw), Pipeline_RCDC_CHD = as.integer(rcdc),
  Gold_CHD = fcase(kw == TRUE, "Yes", rcdc == TRUE, "Partly", default = "No"),
  Pipeline_age = as.character(age), Gold_age_pop = Gold_age_pop,
  `Rule that fired` = rule, `Matched terms` = matched_terms,
  Prior_sample = prior_sample, Prior_CHD_judgment = prior_CHD_judgment, Title = title)])
addStyle(ak, "Key_CHD", FB, rows = 1, cols = 1:18); freezePane(ak, "Key_CHD", firstRow = TRUE)
addFilter(ak, "Key_CHD", rows = 1, cols = 1:18)

addWorksheet(ak, "Key_Age")
writeData(ak, "Key_Age", Age[, .(
  `Review ID` = blind_id, `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY,
  Stratum = stratum, Pipeline_keyword_CHD = as.integer(kw), Pipeline_age = as.character(age),
  Gold_Age = fifelse(kw, as.character(age), "Not CHD"),
  Prior_age_correct = prior_age_correct, Title = title)])
addStyle(ak, "Key_Age", FB, rows = 1, cols = 1:9); freezePane(ak, "Key_Age", firstRow = TRUE)
addFilter(ak, "Key_Age", rows = 1, cols = 1:9)

addWorksheet(ak, "Key_CVD")
writeData(ak, "Key_CVD", CVD[, .(
  `Review ID` = blind_id, `Project number` = FULL_PROJECT_NUM, `Fiscal year` = FY,
  Stratum = stratum, Pipeline_CVD = as.integer(cv), Pipeline_keyword_CHD = as.integer(kw),
  Gold_CVD = fifelse(cv, "Yes", "No"),
  Pipeline_age = as.character(age), Gold_age_pop = Gold_age_pop,
  Gold_age_pop_note = "Derived from CHD age rules (same regex); not a separate CVD-specific age gold",
  Title = title)])
addStyle(ak, "Key_CVD", FB, rows = 1, cols = 1:11); freezePane(ak, "Key_CVD", firstRow = TRUE)
addFilter(ak, "Key_CVD", rows = 1, cols = 1:11)

addWorksheet(ak, "Prior_judgments")
writeData(ak, "Prior_judgments", S[, .(prior_id = id, sample_set = set, FY, project_number = FULL_PROJECT_NUM,
  pipeline_kw = kw, pipeline_rcdc = rcdc, pipeline_age = as.character(age),
  prior_CHD_judgment = prior_CHD, prior_age_correct = prior_age_ok)])
freezePane(ak, "Prior_judgments", firstRow = TRUE)

# Scoring sheet with paste zones + formulas
addWorksheet(ak, "Scoring")
writeData(ak, "Scoring", data.frame(
  Section = c(
    "INSTRUCTIONS",
    "1. From the returned BLIND file, copy columns Review ID + answer from CHD_review into columns A–B below (headers already set in row 3 area for CHD).",
    "2. Or use VLOOKUP: Reviewer_CHD column looks up blind file if you paste blind CHD_review!A:K starting at sheet BlindPaste_CHD (create manually).",
    "3. Simpler: paste Review ID in A, reviewer CHD answer in B, starting row 5. Gold is VLOOKUP from Key_CHD.",
    "4. Same pattern for Age (cols F–G) and CVD (cols K–L).",
    "5. Metrics below update automatically. Cohen kappa uses Agree both Yes / both No style for binary collapses.",
    "",
    "CHD METRICS (binary: Yes vs not-Yes; Partly counted as positive for 'lenient', negative for 'strict')",
    "",
    "AGE METRICS (exact category match; 'Not CHD' matches Gold_Age Not CHD)",
    "",
    "CVD METRICS (Yes vs No; Unsure excluded)"
  ), stringsAsFactors = FALSE
), colNames = FALSE)
# Build long scoring tables starting row 20
writeData(ak, "Scoring", "CHD_Review_ID", startRow = 20, startCol = 1)
writeData(ak, "Scoring", "Reviewer_CHD", startRow = 20, startCol = 2)
writeData(ak, "Scoring", "Gold_CHD", startRow = 20, startCol = 3)
writeData(ak, "Scoring", "Match_strict", startRow = 20, startCol = 4)
writeData(ak, "Scoring", "Match_lenient", startRow = 20, startCol = 5)
# Pre-fill Review IDs and Gold from Key; leave Reviewer blank for paste
writeData(ak, "Scoring", CHD[, .(blind_id)], startRow = 21, startCol = 1, colNames = FALSE)
for (i in seq_len(nrow(CHD))) {
  writeFormula(ak, "Scoring", startRow = 20 + i, startCol = 3,
               x = sprintf('IFERROR(VLOOKUP(A%d,Key_CHD!A:K,11,FALSE),"")', 20 + i))
  # strict: reviewer Yes == Gold Yes; No/Partly/Unsure handling
  writeFormula(ak, "Scoring", startRow = 20 + i, startCol = 4,
               x = sprintf('IF(OR(B%d="",C%d=""),"",IF(B%d=C%d,1,0))', 20 + i, 20 + i, 20 + i, 20 + i))
  writeFormula(ak, "Scoring", startRow = 20 + i, startCol = 5,
               x = sprintf('IF(OR(B%d="",C%d=""),"",IF(OR(AND(OR(B%d="Yes",B%d="Partly"),OR(C%d="Yes",C%d="Partly")),AND(B%d="No",C%d="No")),1,0))',
                           20 + i, 20 + i, 20 + i, 20 + i, 20 + i, 20 + i, 20 + i, 20 + i))
}
nr <- nrow(CHD)
writeData(ak, "Scoring", "CHD n answered", startRow = 3, startCol = 8)
writeFormula(ak, "Scoring", startRow = 3, startCol = 9, x = sprintf('COUNTA(B21:B%d)', 20 + nr))
writeData(ak, "Scoring", "CHD agreement (exact)", startRow = 4, startCol = 8)
writeFormula(ak, "Scoring", startRow = 4, startCol = 9, x = sprintf('IF(COUNTA(B21:B%d)=0,"",AVERAGE(D21:D%d))', 20 + nr, 20 + nr))
writeData(ak, "Scoring", "CHD agreement (lenient Yes/Partly)", startRow = 5, startCol = 8)
writeFormula(ak, "Scoring", startRow = 5, startCol = 9, x = sprintf('IF(COUNTA(B21:B%d)=0,"",AVERAGE(E21:E%d))', 20 + nr, 20 + nr))
# Precision/recall treating Gold Yes as positive, Reviewer Yes as predicted (Unsure excluded)
writeData(ak, "Scoring", "CHD precision (pred Yes, gold Yes)", startRow = 6, startCol = 8)
writeFormula(ak, "Scoring", startRow = 6, startCol = 9,
  x = sprintf('IFERROR(COUNTIFS(B21:B%d,"Yes",C21:C%d,"Yes")/COUNTIF(B21:B%d,"Yes"),"")', 20 + nr, 20 + nr, 20 + nr))
writeData(ak, "Scoring", "CHD recall (gold Yes, pred Yes)", startRow = 7, startCol = 8)
writeFormula(ak, "Scoring", startRow = 7, startCol = 9,
  x = sprintf('IFERROR(COUNTIFS(B21:B%d,"Yes",C21:C%d,"Yes")/COUNTIF(C21:C%d,"Yes"),"")', 20 + nr, 20 + nr, 20 + nr))
# Kappa (3-way collapsed is hard in pure Excel; binary Yes vs other)
writeData(ak, "Scoring", "CHD kappa Yes-vs-other (excl Unsure)", startRow = 8, startCol = 8)
writeFormula(ak, "Scoring", startRow = 8, startCol = 9,
  x = sprintf('IFERROR(LET(po,AVERAGE(IF(B21:B%d<>"Unsure",D21:D%d)),pe,LET(ry,COUNTIFS(B21:B%d,"Yes",B21:B%d,"<>Unsure")/COUNTIF(B21:B%d,"<>Unsure"),gy,COUNTIF(C21:C%d,"Yes")/COUNTA(C21:C%d),ry*gy+(1-ry)*(1-gy)),(po-pe)/(1-pe)),"")',
              20 + nr, 20 + nr, 20 + nr, 20 + nr, 20 + nr, 20 + nr, 20 + nr))

# Age block
ac <- 21 + nr + 3
writeData(ak, "Scoring", "AGE_Review_ID", startRow = ac, startCol = 1)
writeData(ak, "Scoring", "Reviewer_Age", startRow = ac, startCol = 2)
writeData(ak, "Scoring", "Gold_Age", startRow = ac, startCol = 3)
writeData(ak, "Scoring", "Match", startRow = ac, startCol = 4)
writeData(ak, "Scoring", Age[, .(blind_id)], startRow = ac + 1, startCol = 1, colNames = FALSE)
nA <- nrow(Age)
for (i in seq_len(nA)) {
  writeFormula(ak, "Scoring", startRow = ac + i, startCol = 3,
               x = sprintf('IFERROR(VLOOKUP(A%d,Key_Age!A:G,7,FALSE),"")', ac + i))
  writeFormula(ak, "Scoring", startRow = ac + i, startCol = 4,
               x = sprintf('IF(OR(B%d="",C%d=""),"",IF(B%d=C%d,1,0))', ac + i, ac + i, ac + i, ac + i))
}
writeData(ak, "Scoring", "Age n answered", startRow = 10, startCol = 8)
writeFormula(ak, "Scoring", startRow = 10, startCol = 9, x = sprintf('COUNTA(B%d:B%d)', ac + 1, ac + nA))
writeData(ak, "Scoring", "Age agreement (exact)", startRow = 11, startCol = 8)
writeFormula(ak, "Scoring", startRow = 11, startCol = 9, x = sprintf('IF(COUNTA(B%d:B%d)=0,"",AVERAGE(D%d:D%d))', ac + 1, ac + nA, ac + 1, ac + nA))

# CVD block
vc <- ac + nA + 3
writeData(ak, "Scoring", "CVD_Review_ID", startRow = vc, startCol = 1)
writeData(ak, "Scoring", "Reviewer_CVD", startRow = vc, startCol = 2)
writeData(ak, "Scoring", "Gold_CVD", startRow = vc, startCol = 3)
writeData(ak, "Scoring", "Match", startRow = vc, startCol = 4)
writeData(ak, "Scoring", CVD[, .(blind_id)], startRow = vc + 1, startCol = 1, colNames = FALSE)
nV <- nrow(CVD)
for (i in seq_len(nV)) {
  writeFormula(ak, "Scoring", startRow = vc + i, startCol = 3,
               x = sprintf('IFERROR(VLOOKUP(A%d,Key_CVD!A:G,7,FALSE),"")', vc + i))
  writeFormula(ak, "Scoring", startRow = vc + i, startCol = 4,
               x = sprintf('IF(OR(B%d="",C%d="",B%d="Unsure"),"",IF(B%d=C%d,1,0))', vc + i, vc + i, vc + i, vc + i, vc + i))
}
writeData(ak, "Scoring", "CVD n answered (excl Unsure)", startRow = 13, startCol = 8)
writeFormula(ak, "Scoring", startRow = 13, startCol = 9, x = sprintf('COUNTIFS(B%d:B%d,"<>",B%d:B%d,"<>Unsure")', vc + 1, vc + nV, vc + 1, vc + nV))
writeData(ak, "Scoring", "CVD agreement", startRow = 14, startCol = 8)
writeFormula(ak, "Scoring", startRow = 14, startCol = 9, x = sprintf('IFERROR(AVERAGEIF(B%d:B%d,"<>Unsure",D%d:D%d),"")', vc + 1, vc + nV, vc + 1, vc + nV))
writeData(ak, "Scoring", "CVD precision", startRow = 15, startCol = 8)
writeFormula(ak, "Scoring", startRow = 15, startCol = 9,
  x = sprintf('IFERROR(COUNTIFS(B%d:B%d,"Yes",C%d:C%d,"Yes")/COUNTIF(B%d:B%d,"Yes"),"")', vc + 1, vc + nV, vc + 1, vc + nV, vc + 1, vc + nV))
writeData(ak, "Scoring", "CVD recall", startRow = 16, startCol = 8)
writeFormula(ak, "Scoring", startRow = 16, startCol = 9,
  x = sprintf('IFERROR(COUNTIFS(B%d:B%d,"Yes",C%d:C%d,"Yes")/COUNTIF(C%d:C%d,"Yes"),"")', vc + 1, vc + nV, vc + 1, vc + nV, vc + 1, vc + nV))
writeData(ak, "Scoring", "CVD kappa Yes-vs-No (excl Unsure)", startRow = 17, startCol = 8)
writeFormula(ak, "Scoring", startRow = 17, startCol = 9,
  x = sprintf('IFERROR(LET(po,AVERAGEIF(B%d:B%d,"<>Unsure",D%d:D%d),ry,COUNTIF(B%d:B%d,"Yes")/COUNTIFS(B%d:B%d,"<>",B%d:B%d,"<>Unsure"),gy,COUNTIF(C%d:C%d,"Yes")/COUNTA(C%d:C%d),pe,ry*gy+(1-ry)*(1-gy),(po-pe)/(1-pe)),"")',
              vc + 1, vc + nV, vc + 1, vc + nV, vc + 1, vc + nV, vc + 1, vc + nV, vc + 1, vc + nV, vc + 1, vc + nV, vc + 1, vc + nV))


# --- Age-population answers pasted beside CHD block (cols G-H) and CVD (cols G-H of CVD block) ---
writeData(ak, "Scoring", "Reviewer_AgePop_CHD", startRow = 20, startCol = 6)
writeData(ak, "Scoring", "Gold_AgePop_CHD", startRow = 20, startCol = 7)
writeData(ak, "Scoring", "Match_AgePop_CHD", startRow = 20, startCol = 8)
for (i in seq_len(nrow(CHD))) {
  writeFormula(ak, "Scoring", startRow = 20 + i, startCol = 7,
               x = sprintf('IFERROR(VLOOKUP(A%d,Key_CHD!A:N,13,FALSE),"")', 20 + i))
  writeFormula(ak, "Scoring", startRow = 20 + i, startCol = 8,
               x = sprintf('IF(OR(F%d="",G%d=""),"",IF(F%d=G%d,1,0))', 20 + i, 20 + i, 20 + i, 20 + i))
}
writeData(ak, "Scoring", "CHD age-pop n answered", startRow = 18, startCol = 8)
writeFormula(ak, "Scoring", startRow = 18, startCol = 9, x = sprintf('COUNTA(F21:F%d)', 20 + nr))
writeData(ak, "Scoring", "CHD age-pop agreement", startRow = 19, startCol = 8)
writeFormula(ak, "Scoring", startRow = 19, startCol = 9, x = sprintf('IF(COUNTA(F21:F%d)=0,"",AVERAGE(H21:H%d))', 20 + nr, 20 + nr))

# CVD age-pop: columns F-H next to CVD block
writeData(ak, "Scoring", "Reviewer_AgePop_CVD", startRow = vc, startCol = 6)
writeData(ak, "Scoring", "Gold_AgePop_CVD", startRow = vc, startCol = 7)
writeData(ak, "Scoring", "Match_AgePop_CVD", startRow = vc, startCol = 8)
for (i in seq_len(nV)) {
  writeFormula(ak, "Scoring", startRow = vc + i, startCol = 7,
               x = sprintf('IFERROR(VLOOKUP(A%d,Key_CVD!A:I,9,FALSE),"")', vc + i))
  writeFormula(ak, "Scoring", startRow = vc + i, startCol = 8,
               x = sprintf('IF(OR(F%d="",G%d=""),"",IF(F%d=G%d,1,0))', vc + i, vc + i, vc + i, vc + i))
}
writeData(ak, "Scoring", "CVD age-pop n answered", startRow = 18, startCol = 11)
writeData(ak, "Scoring", "CVD age-pop agreement", startRow = 19, startCol = 11)
writeFormula(ak, "Scoring", startRow = 18, startCol = 12, x = sprintf('COUNTA(F%d:F%d)', vc + 1, vc + nV))
writeFormula(ak, "Scoring", startRow = 19, startCol = 12, x = sprintf('IF(COUNTA(F%d:F%d)=0,"",AVERAGE(H%d:H%d))', vc + 1, vc + nV, vc + 1, vc + nV))
writeData(ak, "Scoring", "Paste reviewer Age population (CHD) in column F next to CHD IDs; CVD age-pop in column F of the CVD block. Gold from Key_CHD!Gold_age_pop / Key_CVD!Gold_age_pop.", startRow = 2, startCol = 1)

setColWidths(ak, "Scoring", 1:9, c(18, 16, 14, 12, 14, 12, 12, 42, 14))
addStyle(ak, "Scoring", FB, rows = 20, cols = 1:5)
addStyle(ak, "Scoring", FB, rows = ac, cols = 1:4)
addStyle(ak, "Scoring", FB, rows = vc, cols = 1:4)

key_path <- file.path(CONFIG$out_dir, "chd_manual_check_ANSWER_KEY.xlsx")
try({ ak$core$creator <- ""; ak$core$lastModifiedBy <- ""; ak$core$title <- "CHD manual review ANSWER KEY"; ak$core$subject <- ""; ak$core$description <- "" }, silent = TRUE)
saveWorkbook(ak, key_path, overwrite = TRUE)
say("key -> ", key_path)
say(sprintf("CHD=%d Age=%d CVD=%d", nrow(CHD), nrow(Age), nrow(CVD)))
