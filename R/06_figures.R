#' 06_figures.R -- three figures (Arial, large text; black/grey, color only where it carries meaning).
#'   Fig 1 CHD dollars (bars) and % of all NIH funding (lines: keyword, RCDC), FY2013-2026
#'   Fig 2 CHD dollars by age focus (stacked), FY2013-2026
#'   Fig 3 keyword vs RCDC overlap in dollars, FY2016-2025
#' FY2026 (partial year) is drawn with a lighter fill and labelled.
source("R/00_setup.R")
T <- readRDS(wp("tables.rds")); Y <- T$Y; A <- T$A; O <- T$O[!is.na(FY)]
fam <- CONFIG$font
th <- theme_classic(base_size = 20, base_family = fam) +
  theme(axis.text = element_text(color = "black"), legend.position = "top", legend.title = element_blank(),
        plot.title = element_text(face = "bold", size = 21), plot.caption = element_text(size = 13, hjust = 0))
sv <- function(p, f, w = 12, h = 7.5) {
  ggsave(file.path(CONFIG$out_dir, "figures", paste0(f, ".png")), p, width = w, height = h, dpi = 300)
  ggsave(file.path(CONFIG$out_dir, "figures", paste0(f, ".pdf")), p, width = w, height = h, device = cairo_pdf)
}
yrs <- scale_x_continuous(breaks = 2013:2026, labels = function(x) ifelse(x == 2026, "2026*", x))

# Fig 1 ------------------------------------------------------------------------------
k <- max(Y$chd_USD_M) / max(c(Y$chd_pct_of_NIH, Y$rcdc_pct_of_NIH), na.rm = TRUE) * 0.75
L <- rbind(Y[, .(FY, pct = chd_pct_of_NIH, def = "Keyword classifier")],
           Y[!is.na(rcdc_pct_of_NIH), .(FY, pct = rcdc_pct_of_NIH, def = "NIH RCDC category")])
p1 <- ggplot(Y, aes(FY, chd_USD_M)) +
  geom_col(aes(fill = FY == 2026), width = 0.7, show.legend = FALSE) +
  scale_fill_manual(values = c(`FALSE` = "grey55", `TRUE` = "grey85")) +
  geom_text(aes(label = sprintf("%.0f", chd_USD_M)), vjust = 1.5, size = 5, family = fam, color = "white") +
  geom_line(data = L, aes(FY, pct * k, linetype = def), linewidth = 1.2) +
  geom_point(data = L, aes(FY, pct * k, shape = def), size = 3.2) +
  scale_y_continuous("CHD funding, $ millions", expand = expansion(c(0, 0.05)),
                     sec.axis = sec_axis(~ . / k, name = "% of all NIH funding", labels = function(x) sprintf("%.2f", x))) +
  yrs + labs(x = "Fiscal year", title = "NIH funding for congenital heart disease research",
             caption = "Bars: keyword-classified CHD dollars. *FY2026 partial (records through Oct 20, 2026). RCDC category available FY2016-2025.") + th
sv(p1, "Fig1_CHD_dollars_and_share")

# Fig 2 ------------------------------------------------------------------------------
cols <- c(Pediatric = "#1f5fa8", Adult = "#c0392b", Both = "#7b4fa0", `Basic/non-age-specific` = "grey40", Unclear = "grey78")
p2 <- ggplot(A, aes(FY, USD_M, fill = age)) + geom_col(width = 0.7, color = "white", linewidth = 0.2) +
  scale_fill_manual(values = cols) + yrs +
  scale_y_continuous("CHD funding, $ millions", expand = expansion(c(0, 0.05))) +
  labs(x = "Fiscal year", title = "CHD funding by age focus",
       caption = "Keyword-classified CHD projects; age focus from title/abstract rules. *FY2026 partial.") + th +
  guides(fill = guide_legend(nrow = 2))
sv(p2, "Fig2_CHD_by_age_focus")

# Fig 3 ------------------------------------------------------------------------------
OL <- melt(O[, .(FY, `Both definitions` = both_M, `Keyword only` = kw_only_M, `RCDC only` = rcdc_only_M)], id.vars = "FY")
p3 <- ggplot(OL, aes(FY, value, fill = variable)) + geom_col(width = 0.7) +
  scale_fill_manual(values = c(`Both definitions` = "grey20", `Keyword only` = "grey60", `RCDC only` = "grey88")) +
  scale_x_continuous(breaks = 2016:2025) +
  scale_y_continuous("$ millions", expand = expansion(c(0, 0.05))) +
  labs(x = "Fiscal year", title = "Keyword classifier vs NIH RCDC 'Congenital Heart Disease'",
       caption = "RCDC-only dollars are mostly inherited arrhythmia, cardiomyopathy, valve and heart-development grants (manual review).") + th
sv(p3, "Fig3_keyword_vs_RCDC")
say("figures written")
