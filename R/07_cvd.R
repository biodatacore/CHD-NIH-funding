#' 07_cvd.R -- CHD relative to total cardiovascular (CVD) and total NIH funding, FY2013-2026.
#'
#' CVD denominator = the MAIN cardiovascular definition of the WHR CV analysis
#' (nih-womens-cv-funding, R/03_classify.R, flag `cv` = `broad2`), read from its cached
#' project-level file work_dir/cv/G.rds (WHR repo not run or modified). A record is CV when CV
#' is a substantive part of it, scored on the PARENT record (or all records if no parent):
#'   strict = >=1 strong CV term in title OR >=5 strong CV terms in abstract+PHR
#'   broad2 = strict OR s>=3 OR (s>=2 & w>=2) OR (tw>=1 & s>=1) OR (tw>=1 & w>=6) OR (s>=1 & w>=5)
#' after deleting non-CV usages (tumour angiogenesis, VEGF, heart rate variability, intracranial /
#' portal hypertension, heat stroke, ...). Precision ~84% on hand review. Same project universe
#' and dollars as here, so CVD dollars are a subset of the NIH total.
#' CHD % of CVD uses CHD projects that are ALSO CVD (nested numerator); all-CHD / CVD is
#' reported alongside (CHD projects outside the CV rule are a few % of CHD dollars).
source("R/00_setup.R")
C <- readRDS(wp("C.rds"))
if (!"cv" %in% names(C)) {
  shipped <- wp("shipped_cv.rds")
  if (file.exists(shipped)) {
    G <- readRDS(shipped)[, .(FY, FULL_PROJECT_NUM, cv)]
  } else {
    G <- readRDS(file.path(CONFIG$whr_work, "cv", "G.rds"))[, .(FY, FULL_PROJECT_NUM, cv)]
  }
  C <- merge(C, G, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE)
}
C[is.na(cv), cv := FALSE]

D <- C[, .(NIH_USD_B = sum(USD) / 1e9, CVD_projects = sum(cv), CVD_USD_B = sum(USD[cv]) / 1e9,
           CHD_USD_M = sum(USD[kw]) / 1e6, CHD_in_CVD_projects = sum(kw & cv), CHD_in_CVD_USD_M = sum(USD[kw & cv]) / 1e6,
           CHD_not_CVD_USD_M = sum(USD[kw & !cv]) / 1e6), by = FY][order(FY)]
D[, `:=`(CVD_pct_of_NIH = 100 * CVD_USD_B / NIH_USD_B,
         CHD_pct_of_CVD = 100 * CHD_in_CVD_USD_M / (CVD_USD_B * 1e3),
         CHDall_pct_of_CVD = 100 * CHD_USD_M / (CVD_USD_B * 1e3),
         CHD_pct_of_NIH = 100 * CHD_USD_M / (NIH_USD_B * 1e3),
         note = fifelse(FY == 2026, "PARTIAL fiscal year (records through 2026-10-20)", ""))]
Aa <- C[kw & cv, .(USD_M = sum(USD) / 1e6), by = .(FY, age)]   # age split within CHD∩CVD

trend <- function(v, lab) {
  d <- D[FY %in% CONFIG$trend_years, .(y = FY, v = get(v))]
  f <- lm(log(v) ~ y, d); b <- coef(f)[2]; ci <- confint(f)[2, ]
  data.table(series = lab, start_FY2013 = d$v[1], end_FY2025 = d$v[nrow(d)],
             CAGR_pct = 100 * ((d$v[nrow(d)] / d$v[1])^(1 / 12) - 1),
             APC_pct = 100 * (exp(b) - 1), APC_lo = 100 * (exp(ci[1]) - 1), APC_hi = 100 * (exp(ci[2]) - 1),
             p = summary(f)$coefficients[2, 4])
}
Tr <- rbind(trend("NIH_USD_B", "Total NIH ($B)"), trend("CVD_USD_B", "Total CVD ($B)"),
            trend("CVD_pct_of_NIH", "CVD % of NIH"), trend("CHD_in_CVD_USD_M", "CHD within CVD ($M)"),
            trend("CHD_pct_of_CVD", "CHD % of CVD"), trend("CHD_USD_M", "CHD all ($M)"), trend("CHD_pct_of_NIH", "CHD % of NIH"))
# pooled period comparison
per <- function(y) D[FY %in% y, .(CHD_pct_of_CVD = 100 * sum(CHD_in_CVD_USD_M) / (1e3 * sum(CVD_USD_B)),
                                  CHD_pct_of_NIH = 100 * sum(CHD_USD_M) / (1e3 * sum(NIH_USD_B)),
                                  CVD_pct_of_NIH = 100 * sum(CVD_USD_B) / sum(NIH_USD_B))]
Pp <- rbind(cbind(period = "FY2013-2015", per(2013:2015)), cbind(period = "FY2023-2025", per(2023:2025)))

# ---- workbook: add/replace sheets -------------------------------------------------------
f <- file.path(CONFIG$out_dir, "chd_nih_funding_2013_2026.xlsx")
wb <- loadWorkbook(f); hs <- createStyle(fontName = "Arial", textDecoration = "bold")
r2 <- function(d) { d <- copy(d); for (j in names(d)) if (is.numeric(d[[j]]) && !is.integer(d[[j]])) set(d, j = j, value = round(d[[j]], 4)); d }
put <- function(n, d) { if (n %in% names(wb)) removeWorksheet(wb, n); addWorksheet(wb, n)
  writeData(wb, n, d, headerStyle = hs); setColWidths(wb, n, seq_len(ncol(d)), "auto"); freezePane(wb, n, firstRow = TRUE) }
put("CVD_NIH_context", r2(D)); put("CVD_trends", r2(Tr)); put("CVD_periods", r2(Pp))
put("CHD_in_CVD_by_age_USD_M", r2(dcast(Aa, FY ~ age, value.var = "USD_M", fill = 0)))
put("CVD_definition", data.table(item = c("CVD definition", "CHD % of CVD", "Source"), text = c(
  "Main CV definition of the women's CV funding analysis (broad2): CV term in the title or repeated CV terms in abstract/PHR, scored on the parent record, non-CV usages removed; ~84% precision on hand review.",
  "Numerator = keyword-CHD projects that also meet the CVD definition (nested); all-CHD/CVD also shown.",
  "Project-level CV flags from the WHR CV pipeline cache (cv/G.rds); same universe and dollars as this project.")))
saveWorkbook(wb, f, overwrite = TRUE)

# ---- figures ----------------------------------------------------------------------------
fam <- CONFIG$font
th <- theme_classic(base_size = 20, base_family = fam) +
  theme(axis.text = element_text(color = "black"), legend.position = "top", legend.title = element_blank(),
        plot.title = element_text(face = "bold", size = 20), plot.caption = element_text(size = 13, hjust = 0))
yrs <- scale_x_continuous(breaks = 2013:2026, labels = function(x) ifelse(x == 2026, "2026*", x))
cols <- c(Pediatric = "#1f5fa8", Adult = "#c0392b", Both = "#7b4fa0", `Basic/non-age-specific` = "grey45", Unclear = "grey80")
sv <- function(p, n, w = 12, h = 7.5) {
  ggsave(file.path(CONFIG$out_dir, "figures", paste0(n, ".png")), p, width = w, height = h, dpi = 300)
  ggsave(file.path(CONFIG$out_dir, "figures", paste0(n, ".pdf")), p, width = w, height = h, device = cairo_pdf)
}
panel <- function(bars, pct, ymax_pct, ttl, ylab2, cap) {
  k <- max(D[[bars]]) * 1.15 / ymax_pct
  B <- if (bars == "CHD_in_CVD_USD_M") Aa else C[kw == TRUE, .(USD_M = sum(USD) / 1e6), by = .(FY, age)]
  ggplot() +
    geom_col(data = B, aes(FY, USD_M, fill = age, alpha = FY == 2026), width = 0.7) +
    scale_alpha_manual(values = c(`FALSE` = 1, `TRUE` = 0.45), guide = "none") +
    scale_fill_manual(values = cols) +
    geom_line(data = D, aes(FY, get(pct) * k), linewidth = 1.3) +
    geom_point(data = D, aes(FY, get(pct) * k), size = 3.3, shape = 21, fill = "white", stroke = 1.3) +
    geom_text(data = D, aes(FY, get(pct) * k, label = sprintf("%.2f%%", get(pct))), vjust = -1.1, size = 4.6, family = fam) +
    scale_y_continuous("CHD funding, $ millions", limits = c(0, max(D[[bars]]) * 1.25), expand = expansion(c(0, 0)),
                       sec.axis = sec_axis(~ . / k, name = ylab2, labels = function(x) sprintf("%.2f", x))) +
    yrs + labs(x = "Fiscal year", title = ttl, caption = cap) + th + guides(fill = guide_legend(nrow = 2))
}
pA <- panel("CHD_in_CVD_USD_M", "CHD_pct_of_CVD", max(D$CHD_pct_of_CVD), "CHD funding relative to total NIH cardiovascular funding",
            "CHD, % of NIH CVD funding", "Bars: CHD dollars by age focus (CHD projects within the CVD definition). Line: CHD as % of total NIH CVD funding.\n*FY2026 partial (records through Oct 20, 2026), shown lighter.")
pB <- panel("CHD_USD_M", "CHD_pct_of_NIH", max(D$CHD_pct_of_NIH), "CHD funding relative to total NIH funding",
            "CHD, % of all NIH funding", "Bars: CHD dollars by age focus (all keyword-classified CHD projects). Line: CHD as % of all NIH funding.\n*FY2026 partial (records through Oct 20, 2026), shown lighter.")
sv(pA, "Fig4_CHD_vs_CVD"); sv(pB, "Fig5_CHD_vs_NIH")
# context: NIH total and CVD total ($B) with CVD share labels
X <- melt(D[, .(FY, `All NIH` = NIH_USD_B, `Cardiovascular (CVD)` = CVD_USD_B)], id.vars = "FY")
pC <- ggplot(X, aes(FY, value, fill = variable, alpha = FY == 2026)) +
  geom_col(position = "identity", width = 0.7) +
  scale_fill_manual(values = c(`All NIH` = "grey80", `Cardiovascular (CVD)` = "grey25")) +
  scale_alpha_manual(values = c(`FALSE` = 1, `TRUE` = 0.5), guide = "none") +
  geom_text(data = D, aes(FY, CVD_USD_B, label = sprintf("%.1f%%", CVD_pct_of_NIH)), inherit.aes = FALSE,
            vjust = -0.6, size = 4.6, family = fam) +
  scale_y_continuous("$ billions", expand = expansion(c(0, 0.05))) + yrs +
  labs(x = "Fiscal year", title = "NIH cardiovascular funding within total NIH funding",
       caption = "Labels: CVD as % of all NIH funding. *FY2026 partial.") + th
sv(pC, "Fig6_CVD_vs_NIH_context")
print(r2(D[, .(FY, NIH_USD_B, CVD_USD_B, CVD_pct_of_NIH, CHD_in_CVD_USD_M, CHD_pct_of_CVD, CHDall_pct_of_CVD, CHD_pct_of_NIH)]))
print(r2(Tr)); print(r2(Pp))
# combined two-panel version (A: vs CVD, B: vs NIH) with one shared legend
if (requireNamespace("patchwork", quietly = TRUE)) {
  library(patchwork)
  pAB <- (pA + labs(title = "A. CHD relative to total NIH CVD funding", caption = NULL)) /
         (pB + labs(title = "B. CHD relative to total NIH funding",
                    caption = "Bars: CHD dollars by age focus (A: CHD projects within the CVD definition; B: all CHD projects). Lines: CHD share.\n*FY2026 partial (records through Oct 20, 2026), shown lighter.")) +
         plot_layout(guides = "collect") & theme(legend.position = "top")
  sv(pAB, "Fig4-5_CHD_vs_CVD_and_NIH_two_panel", w = 12, h = 13.5)
}
