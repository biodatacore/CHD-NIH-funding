#' 08_wonder.R -- US congenital heart disease (CHD) deaths relative to CVD and heart-disease
#' deaths, 2013-2024 (CDC WONDER), plotted alongside the CHD share of NIH CVD funding (Fig 4).
#'
#' SOURCE  CDC WONDER XML API (national-level queries only; >= 15 s between requests).
#'         Final NCHS mortality files; one consistent splice at 2018 (same as the WHR CV analysis):
#'           2013-2017  D76 Underlying Cause 1999-2020 (bridged race) and D77 Multiple Cause 1999-2020
#'           2018-2024  D158 Underlying Cause 2018-2024 (single race) and D157 Multiple Cause 2018-2024
#'         (2024 comes from the FINAL 2018-2024 files, not the provisional database.) Race is not
#'         used, so the bridged vs single-race change affects only the file used; 2018-2020 are
#'         fetched from BOTH files to quantify the splice.
#' QUERIES (group by Year; ages filtered by single-year age; sex-pooled; no age adjustment)
#'   CHD, underlying cause   UCD ICD-10 Q20-Q26
#'   CHD, any mention        MCD ICD-10 Q20-Q26 anywhere on the certificate (multiple cause)
#'   All CVD                 UCD I00-I99 (Diseases of the circulatory system)
#'   Heart disease           UCD 113-cause list GR113-054 (I00-I09, I11, I13, I20-I51)
#'   each for ages 0-17 ("pediatric") and all ages; adult (18+) = all ages - pediatric
#'   (deaths with age not stated, a few per year, fall in "adult").
#' Denominators are UNDERLYING-cause CVD / heart deaths; "any mention" CHD is therefore not a
#' strict subset of the denominator (a CHD-mention death can have a non-CVD underlying cause).
#' WONDER suppresses counts 1-9; such cells are recorded as NA and never imputed.
#' Raw XML responses are saved in data/wonder/. Usage: Rscript R/08_wonder.R [--refetch]
#' With the XML already shipped, use --parse-only (or CHD_WONDER_PARSE_ONLY=1)
#' to rebuild data/wonder/wonder_long.csv and skip the v1 workbook/figures.
source("R/00_setup.R")
WDIR <- "data/wonder"; dir.create(WDIR, showWarnings = FALSE)
refetch <- "--refetch" %in% commandArgs(trailingOnly = TRUE)
parse_only <- "--parse-only" %in% commandArgs(trailingOnly = TRUE) ||
  identical(Sys.getenv("CHD_WONDER_PARSE_ONLY"), "1")
if (refetch) suppressMessages(library(xml2))
URL <- function(db) paste0("https://wonder.cdc.gov/controller/datarequest/", db)

#' POST helper (application/x-www-form-urlencoded, as WONDER requires)
post <- function(db, body) {
  h <- curl::new_handle(); curl::handle_setopt(h, postfields = body, timeout = 600)
  curl::handle_setheaders(h, "Content-Type" = "application/x-www-form-urlencoded")
  r <- curl::curl_fetch_memory(URL(db), handle = h); list(status = r$status_code, x = enc2utf8(rawToChar(r$content)))
}
#' Default request parameters of a database, scraped from its public query form (after the
#' data-use agreement page), so that every unspecified option keeps WONDER's own default.
form_defaults <- function(db) {
  f <- file.path(WDIR, sprintf("form_%s.html", db))
  if (!file.exists(f)) { writeLines(post(db, "stage=about&action-I%20Agree=I%20Agree")$x, f); Sys.sleep(5) }
  d <- read_html(f); p <- list()
  for (n in xml_find_all(d, "//input[@name]")) {
    nm <- xml_attr(n, "name"); ty <- tolower(xml_attr(n, "type")); if (is.na(ty)) ty <- "text"
    v <- xml_attr(n, "value"); if (is.na(v)) v <- ""
    if (ty %in% c("submit", "button", "reset", "image")) next
    if (ty %in% c("radio", "checkbox")) { if (!is.na(xml_attr(n, "checked"))) p[[nm]] <- c(if (ty == "checkbox") p[[nm]], v); next }
    if (is.null(p[[nm]])) p[[nm]] <- v
  }
  for (s in xml_find_all(d, "//select[@name]")) {
    nm <- xml_attr(s, "name"); o <- xml_find_all(s, ".//option[@selected]")
    if (!length(o)) o <- xml_find_all(s, ".//option")[1]
    if (!length(o)) next
    p[[nm]] <- vapply(seq_along(o), function(i) { v <- xml_attr(o[[i]], "value"); if (is.na(v)) xml_text(o[[i]]) else v }, "")
  }
  p[!grepl("^(finder-action|tab-|action-Reset|action-Save|saved_id|O_export)", names(p))]
}
toxml <- function(p) paste0("<request-parameters>", paste0(vapply(names(p), function(n)
  paste0("<parameter><name>", n, "</name>", paste0("<value>", p[[n]], "</value>", collapse = ""), "</parameter>"), ""), collapse = ""), "</request-parameters>")

#' Build and send one query. cause: list(type = "ucd_icd" | "ucd_113" | "mcd", codes = ...)
wonder <- function(db, cause, ages = NULL, tag) {
  f <- file.path(WDIR, paste0(tag, ".xml"))
  if (!file.exists(f) || refetch) {
    V <- function(v) paste0(db, ".", v)
    p <- form_defaults(db); p$stage <- "request"; p[["action-Send"]] <- "Send"; p$O_aar <- "aar_none"
    p$O_show_suppressed <- "true"; p$O_show_zeros <- "true"; p$O_show_totals <- "false"
    p$B_1 <- V("V1-level1"); for (i in 2:5) p[[paste0("B_", i)]] <- "*None*"
    if (cause$type == "ucd_icd") { p$O_ucd <- V("V2"); p$O_V2_fmode <- "freg"; p[[paste0("F_", V("V2"))]] <- cause$codes }
    if (cause$type == "ucd_113") { p$O_ucd <- V("V4"); p[[paste0("V_", V("V4"))]] <- cause$codes }
    if (cause$type == "mcd") { p$O_mcd <- V("V13"); p$O_V13_fmode <- "freg"; p[[paste0("F_", V("V13"))]] <- cause$codes
      p[[paste0("V_", V("V13"))]] <- ""; p[[paste0("V_", V("V13_AND"))]] <- "" }
    if (!is.null(ages)) { p$O_age <- V("V52"); p[[paste0("V_", V("V52"))]] <- ages }
    r <- post(db, paste0("request_xml=", curl::curl_escape(toxml(p)), "&accept_datause_restrictions=true"))
    if (r$status != 200) stop(db, " ", tag, ": HTTP ", r$status, " ", substr(gsub("\\s+", " ", r$x), 1, 400))
    writeLines(r$x, f); say("fetched ", tag); Sys.sleep(16)
  }
  x <- paste(readLines(f, warn = FALSE), collapse = "\n")
  rr <- regmatches(x, gregexpr("<r>.*?</r>", x))[[1]]
  rbindlist(lapply(rr, function(r) { c <- trimws(sub('^<c (l|v)="', "", regmatches(r, gregexpr('<c (l|v)="[^"]*', r))[[1]]))
    data.table(year = as.integer(c[1]), deaths_raw = c[2]) }))[, deaths := suppressWarnings(as.integer(gsub(",", "", deaths_raw)))][]
}

CAUSES <- list(chd_ucd = list(type = "ucd_icd", codes = paste0("Q", 20:26), mcd = FALSE),
               chd_any = list(type = "mcd", codes = paste0("Q", 20:26), mcd = TRUE),
               cvd = list(type = "ucd_icd", codes = "I00-I99", mcd = FALSE),
               heart = list(type = "ucd_113", codes = "GR113-054", mcd = FALSE))
AGES <- list(all = NULL, ped = as.character(0:17))
SRC <- list(bridged = c(ucd = "D76", mcd = "D77"), single = c(ucd = "D158", mcd = "D157"))
R <- rbindlist(lapply(names(SRC), function(s) rbindlist(lapply(names(CAUSES), function(k) rbindlist(lapply(names(AGES), function(a) {
  cz <- CAUSES[[k]]; db <- SRC[[s]][[if (cz$mcd) "mcd" else "ucd"]]
  if (cz$type == "ucd_icd" && cz$codes[1] == "I00-I99") cz$codes <- "I00-I99"
  wonder(db, cz, AGES[[a]], paste(db, k, a, sep = "_"))[, `:=`(source = s, database = db, measure = k, age = a)]
}))))))
fwrite(R, file.path(WDIR, "wonder_long.csv"))
if (isTRUE(parse_only)) {
  say("wrote data/wonder/wonder_long.csv (", nrow(R), " rows); parse-only, skipping v1 workbook/figures")
} else {

# ---- splice: bridged files for 2013-2017, single-race files for 2018-2024 ----------------------
S <- R[(source == "bridged" & year %in% 2013:2017) | (source == "single" & year %in% 2018:2024)]
W <- dcast(S, year ~ measure + age, value.var = "deaths")
W[, `:=`(chd_ucd_adult = chd_ucd_all - chd_ucd_ped, chd_any_adult = chd_any_all - chd_any_ped,
         cvd_adult = cvd_all - cvd_ped, heart_adult = heart_all - heart_ped)]
# ICD-10 Q20-Q26 lies OUTSIDE chapter I (I00-I99), so CHD underlying-cause deaths are added to
# both denominators: CVD+CHD = I00-I99 + Q20-Q26 and heart+CHD = GR113-054 + Q20-Q26 (disjoint).
for (g in c("all", "ped", "adult")) {
  W[, (paste0("cvd_", g)) := get(paste0("cvd_", g)) + get(paste0("chd_ucd_", g))]
  W[, (paste0("heart_", g)) := get(paste0("heart_", g)) + get(paste0("chd_ucd_", g))]
}
for (g in c("all", "ped", "adult")) for (m in c("chd_ucd", "chd_any")) for (d in c("cvd", "heart"))
  W[, (sprintf("%s_pct_of_%s_%s", m, d, g)) := 100 * get(paste(m, g, sep = "_")) / get(paste(d, g, sep = "_"))]
W[, file_note := fifelse(year <= 2017, "D76 (UCD) / D77 (MCD), bridged-race final", "D158 (UCD) / D157 (MCD), single-race final")]
# overlap 2018-2020: same counts in both file families?
OV <- dcast(R[year %in% 2018:2020], year + measure + age ~ source, value.var = "deaths")[, diff := single - bridged]

# ---- funding comparison (Fig 4 series) --------------------------------------------------------
Fd <- as.data.table(openxlsx::read.xlsx(file.path(CONFIG$out_dir, "chd_nih_funding_2013_2026.xlsx"), sheet = "CVD_NIH_context"))[, .(year = FY, CHD_pct_of_CVD_funding = CHD_pct_of_CVD)]
W <- merge(W, Fd, by = "year", all.x = TRUE)

trend <- function(v, lab) { d <- data.table(y = W$year, v = W[[v]])[y %in% 2013:2024 & !is.na(v)]
  f <- lm(log(v) ~ y, d); ci <- confint(f)[2, ]
  data.table(series = lab, y2013 = d$v[1], y2024 = d$v[nrow(d)], APC_pct = 100 * (exp(coef(f)[2]) - 1),
             APC_lo = 100 * (exp(ci[1]) - 1), APC_hi = 100 * (exp(ci[2]) - 1), p = summary(f)$coefficients[2, 4]) }
TR <- rbindlist(lapply(grep("_pct_of_|deaths|chd_(ucd|any)_(all|ped|adult)$|CHD_pct", names(W), value = TRUE), function(v) trend(v, v)))

# ---- workbook ----------------------------------------------------------------------------------
f <- file.path(CONFIG$out_dir, "chd_nih_funding_2013_2026.xlsx"); wb <- loadWorkbook(f)
hs <- createStyle(fontName = "Arial", textDecoration = "bold")
r2 <- function(d) { d <- copy(d); for (j in names(d)) if (is.numeric(d[[j]]) && !is.integer(d[[j]])) set(d, j = j, value = round(d[[j]], 4)); d }
put <- function(n, d) { if (n %in% names(wb)) removeWorksheet(wb, n); addWorksheet(wb, n)
  writeData(wb, n, d, headerStyle = hs); setColWidths(wb, n, seq_len(ncol(d)), "auto"); freezePane(wb, n, firstRow = TRUE) }
put("Mortality_yearly", r2(W)); put("Mortality_trends", r2(TR)); put("Mortality_splice_check", OV)
put("Mortality_raw_long", R[, .(year, source, database, measure, age, deaths_raw, deaths)])
put("Mortality_methods", data.table(item = c("Source", "CHD", "Denominators", "Ages", "Splice", "Suppression", "Retrieved"), text = c(
  "CDC WONDER XML API, national data, final NCHS files: D76/D77 (1999-2020, bridged race) for 2013-2017; D158/D157 (2018-2024, single race) for 2018-2024.",
  "Underlying cause ICD-10 Q20-Q26; any mention = multiple cause Q20-Q26 anywhere on the death certificate.",
  "Underlying-cause all CVD (I00-I99) and diseases of heart (113-cause list GR113-054), each PLUS underlying-cause CHD (Q20-Q26), because Q codes lie outside ICD-10 chapter I. Columns cvd_* and heart_* already include the added CHD deaths.",
  "Pediatric = single-year ages 0-17; adult = all ages minus pediatric (includes age not stated).",
  "2018-2020 available in both file families; differences reported in Mortality_splice_check.",
  "WONDER suppresses counts 1-9; none of the yearly cells used here were suppressed unless shown as NA.",
  as.character(Sys.Date()))))
saveWorkbook(wb, f, overwrite = TRUE)

# ---- figures -----------------------------------------------------------------------------------
fam <- CONFIG$font
th <- theme_classic(base_size = 20, base_family = fam) +
  theme(axis.text = element_text(color = "black"), legend.position = "top", legend.title = element_blank(),
        plot.title = element_text(face = "bold", size = 20), plot.caption = element_text(size = 12, hjust = 0), plot.caption.position = "plot",
        strip.background = element_blank(), strip.text = element_text(face = "bold", size = 18), legend.key.width = unit(1.8, "cm"))
CAP <- paste0("Mortality: CDC WONDER final files (2013-2017 bridged-race D76/D77; 2018-2024 single-race D158/D157; one splice at 2018; race not used). ",
  "CHD = ICD-10 Q20-Q26; denominators = underlying-cause CVD (I00-I99) or heart disease plus underlying-cause CHD. Underlying cause misses many\nadult CHD deaths, so any mention is preferred for adults; any-mention CHD deaths can have a non-CVD underlying cause, so they are not a strict subset of the denominator. ",
  "Counts 1-9 are suppressed by WONDER\n(not imputed). Death-certificate coding and certification vary. 2024 is from the final 2018-2024 file (provisional data not used). ",
  "Funding share (FY) and mortality share (calendar year) are ecological\ncomparisons and imply no causal relation. Pediatric = ages 0-17; adult = 18+ (incl. age not stated).")
wrapc <- function(x) paste(strwrap(gsub("\n", " ", x), width = 150), collapse = "\n")
CAP <- wrapc(CAP)
sv <- function(p, n, w = 13, h = 9.5) {
  ggsave(file.path(CONFIG$out_dir, "figures", paste0(n, ".png")), p, width = w, height = h, dpi = 300)
  ggsave(file.path(CONFIG$out_dir, "figures", paste0(n, ".pdf")), p, width = w, height = h, device = cairo_pdf) }
L <- rbind(
  W[, .(year, panel = "CHD share of CVD deaths (I00-I99 + Q20-Q26)", series = "CHD deaths, any mention", age = c("All ages"), v = chd_any_pct_of_cvd_all)],
  W[, .(year, panel = "CHD share of CVD deaths (I00-I99 + Q20-Q26)", series = "CHD deaths, underlying cause", age = "All ages", v = chd_ucd_pct_of_cvd_all)],
  W[, .(year, panel = "CHD share of heart-disease deaths (+ Q20-Q26)", series = "CHD deaths, any mention", age = "All ages", v = chd_any_pct_of_heart_all)],
  W[, .(year, panel = "CHD share of heart-disease deaths (+ Q20-Q26)", series = "CHD deaths, underlying cause", age = "All ages", v = chd_ucd_pct_of_heart_all)],
  W[!is.na(CHD_pct_of_CVD_funding), .(year, panel = "CHD share of CVD deaths (I00-I99 + Q20-Q26)", series = "CHD share of NIH CVD funding", age = "All ages", v = CHD_pct_of_CVD_funding)],
  W[!is.na(CHD_pct_of_CVD_funding), .(year, panel = "CHD share of heart-disease deaths (+ Q20-Q26)", series = "CHD share of NIH CVD funding", age = "All ages", v = CHD_pct_of_CVD_funding)])
lt <- c(`CHD share of NIH CVD funding` = "solid", `CHD deaths, any mention` = "solid", `CHD deaths, underlying cause` = "22")
cl <- c(`CHD share of NIH CVD funding` = "#c0392b", `CHD deaths, any mention` = "black", `CHD deaths, underlying cause` = "black")
p7 <- ggplot(L, aes(year, v, linetype = series, color = series, shape = series)) + geom_line(linewidth = 1.2) + geom_point(size = 3, fill = "white") +
  facet_wrap(~panel, nrow = 1) + scale_linetype_manual(values = lt) + scale_color_manual(values = cl) +
  scale_shape_manual(values = c(`CHD share of NIH CVD funding` = 16, `CHD deaths, any mention` = 21, `CHD deaths, underlying cause` = 21)) +
  scale_x_continuous(breaks = seq(2013, 2024, 2)) + scale_y_continuous("Percent", limits = c(0, NA), expand = expansion(c(0, 0.08))) +
  labs(x = "Year (funding: fiscal year)", title = "CHD share of cardiovascular deaths vs CHD share of NIH CVD funding, all ages", caption = CAP) +
  th + guides(linetype = guide_legend(nrow = 1)) + theme(legend.text = element_text(size = 15))
sv(p7, "Fig7_CHD_deaths_vs_funding_share")
# by age group (CVD denominator): pediatric vs adult, any mention (solid) and underlying (dashed)
# Pediatric any-mention is NOT plotted: most pediatric CHD-mention deaths have a non-CVD
# underlying cause (eg, other congenital anomalies, perinatal conditions), so the ratio is
# ~87-94% of CVD+CHD deaths and >100% of heart+CHD deaths -- not a meaningful share (kept in workbook).
LA <- rbind(W[, .(year, grp = "Pediatric (<18 y)", series = "Underlying cause", v = chd_ucd_pct_of_cvd_ped)],
            W[, .(year, grp = "Adult (18+ y)", series = "Any mention", v = chd_any_pct_of_cvd_adult)],
            W[, .(year, grp = "Adult (18+ y)", series = "Underlying cause", v = chd_ucd_pct_of_cvd_adult)])
LA[, grp := factor(grp, c("Pediatric (<18 y)", "Adult (18+ y)"))]
p8 <- ggplot(LA, aes(year, v, linetype = series)) + geom_line(linewidth = 1.2) + geom_point(size = 3, shape = 21, fill = "white") +
  facet_wrap(~grp, nrow = 1, scales = "free_y") + scale_linetype_manual(values = c(`Any mention` = "solid", `Underlying cause` = "22")) +
  scale_x_continuous(breaks = seq(2013, 2024, 2)) + scale_y_continuous("CHD deaths, % of CVD deaths in age group", limits = c(0, NA), expand = expansion(c(0, 0.08))) +
  labs(x = "Year", title = "CHD share of cardiovascular deaths by age group",
       caption = wrapc(paste0(CAP, " Pediatric any-mention share not shown: most such deaths have a non-CVD underlying cause, so the ratio is not a share (87-94%; in workbook)."))) + th
sv(p8, "Fig8_CHD_deaths_share_by_age")
print(r2(W[, .(year, chd_ucd_all, chd_any_all, chd_any_ped, chd_any_adult, cvd_all, heart_all,
               ucd_cvd = chd_ucd_pct_of_cvd_all, any_cvd = chd_any_pct_of_cvd_all, any_heart = chd_any_pct_of_heart_all,
               any_cvd_ped = chd_any_pct_of_cvd_ped, any_cvd_adult = chd_any_pct_of_cvd_adult, ucd_cvd_adult = chd_ucd_pct_of_cvd_adult, fund = CHD_pct_of_CVD_funding)]))
print(r2(TR[grepl("pct", series)])); print(OV[diff != 0 | is.na(diff)])
}
