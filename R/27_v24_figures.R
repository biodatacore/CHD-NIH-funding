# 27_v24_figures.R -- base-R port of R/22_v24_figures.py
# Arial, no grid, color only for age groups, FY2026 lighter and labelled 2026*.
# Layouts, titles, captions, and plotted values follow the Python figures.
# Pixel identity is not required.

if (!exists("chd_root")) {
  if (file.exists("R/chd_v24_metrics.R")) source("R/chd_v24_metrics.R")
}

AGE_COLORS_V24 <- c(
  Pediatric = "#1f5fa8",
  Adult = "#c0392b",
  Both = "#7b4fa0",
  `Not age-specific` = "grey45"
)
AGE_ORDER_V24 <- names(AGE_COLORS_V24)

# Register Arial with cairo / fontconfig when the TTF is present.
.arial_candidates <- c(
  "/home/box/.fonts/arial/arial.ttf",
  "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf",
  "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
)
.ARIAL_TTF <- Filter(file.exists, .arial_candidates)[1]
if (is.na(.ARIAL_TTF)) .ARIAL_TTF <- NULL

chd_fig_par <- function(right_spine = FALSE) {
  par(family = "Arial",
      las = 1, xaxs = "i", yaxs = "i",
      cex.main = 1.15, cex.lab = 1.05, cex.axis = 0.95,
      col.axis = "black", col.lab = "black", col.main = "black",
      fg = "black",
      tcl = -0.3, mgp = c(2.4, 0.6, 0),
      lend = "butt")
}

chd_classic <- function(right_spine = FALSE) {
  box(bty = if (right_spine) "u" else "l")
}

fy_ticks <- function(years = 2013:2026) {
  axis(1, at = years, labels = ifelse(years == 2026, "2026*", as.character(years)),
       family = "Arial")
}

add_caption <- function(text, cex = 0.72) {
  # Draw in the outer margin (figure inches).
  usr <- par("usr")
  pin <- par("pin")
  mai <- par("mai")
  fin <- par("fin")
  # Use mtext in the bottom outer margin, left aligned.
  wrapped <- paste(strwrap(text, width = 118), collapse = "\n")
  mtext(wrapped, side = 1, line = 4.2, adj = 0, cex = cex, family = "Arial")
}

save_open <- function(stem, out, width, height, also_tif = FALSE, also_pdf = TRUE) {
  # Opens a PNG cairo device; caller plots, then chd_save_close() writes pdf/tif copies.
  png_path <- file.path(out, paste0(stem, ".png"))
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  png(png_path, width = width, height = height, units = "in", res = 300,
      type = "cairo", family = "Arial", bg = "white", pointsize = 12)
  assign(".chd_fig_meta", list(stem = stem, out = out, width = width, height = height,
                               also_tif = also_tif, also_pdf = also_pdf, png = png_path),
         envir = .GlobalEnv)
}

chd_save_close <- function() {
  meta <- get(".chd_fig_meta", envir = .GlobalEnv)
  dev.off()
  if (isTRUE(meta$also_pdf) || isTRUE(meta$also_tif)) {
    # Re-plot is handled by the caller wrapping in chd_with_device().
  }
  invisible(meta$png)
}

# Evaluate `expr` on png, pdf, and optionally tif cairo devices.
chd_with_device <- function(stem, out, width, height, also_tif = FALSE, expr) {
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  png_path <- file.path(out, paste0(stem, ".png"))
  png(png_path, width = width, height = height, units = "in", res = 300,
      type = "cairo", family = "Arial", bg = "white", pointsize = 12)
  eval.parent(substitute(expr))
  dev.off()
  if (TRUE) {
    cairo_pdf(file.path(out, paste0(stem, ".pdf")), width = width, height = height,
              family = "Arial", bg = "white")
    eval.parent(substitute(expr))
    dev.off()
  }
  if (isTRUE(also_tif)) {
    tiff(file.path(out, paste0(stem, ".tif")), width = width, height = height,
         units = "in", res = 300, compression = "lzw", type = "cairo",
         family = "Arial", bg = "white", pointsize = 12)
    eval.parent(substitute(expr))
    dev.off()
  }
  invisible(png_path)
}

stacked_bars <- function(age_df, age_order = AGE_ORDER_V24, colors = AGE_COLORS_V24,
                         value = "USD_M", width = 0.7) {
  years <- 2013:2026
  bottoms <- setNames(rep(0, length(years)), as.character(years))
  for (age in age_order) {
    sub <- age_df[as.character(age_df$age) == age, , drop = FALSE]
    h <- setNames(rep(0, length(years)), as.character(years))
    if (nrow(sub)) {
      h[as.character(sub$FY)] <- as.numeric(sub[[value]])
      h[is.na(h)] <- 0
    }
    bot <- unname(bottoms)
    complete <- ifelse(years == 2026, 0, unname(h))
    y2026 <- ifelse(years == 2026, unname(h), 0)
    rect(years - width / 2, bot, years + width / 2, bot + complete,
         col = colors[[age]], border = NA)
    rect(years - width / 2, bot, years + width / 2, bot + y2026,
         col = adjustcolor(colors[[age]], alpha.f = 0.45), border = NA)
    bottoms <- bottoms + h
  }
  invisible(max(bottoms))
}

age_ymax <- function(age_df, value = "USD_M") {
  years <- 2013:2026
  tot <- setNames(rep(0, length(years)), as.character(years))
  if (nrow(age_df)) {
    ag <- tapply(as.numeric(age_df[[value]]), age_df$FY, sum, default = 0)
    tot[as.character(names(ag))] <- as.numeric(ag)
  }
  max(tot, na.rm = TRUE)
}

legend_top <- function(legend_expr) {
  # Placeholder: legends are drawn in the top outer margin via the plot itself.
  invisible(NULL)
}

# ---- individual figures ----

fig1 <- function(D, out) {
  chd_with_device("Fig1_CHD_dollars_and_share", out, 12, 7.5, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        mar = c(6.2, 4.2, 3.6, 4.4), oma = c(0, 0, 0.2, 0),
        cex.main = 1.35, cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.6, 0.6, 0))
    years <- D$FY
    dollars <- D$CHD_USD_M
    cols <- ifelse(years != 2026, "grey55", "grey85")
    rcdc_max <- max(D$rcdc_pct_of_NIH, na.rm = TRUE)
    k <- max(dollars) / max(max(D$CHD_pct_of_NIH), rcdc_max) * 0.92
    ytop <- max(dollars) * 1.08
    plot(NA, xlim = c(2012.4, 2026.6), ylim = c(0, ytop), axes = FALSE,
         xlab = "Fiscal year", ylab = "CHD funding, $ millions",
         main = "NIH funding for congenital heart disease research")
    rect(years - 0.35, 0, years + 0.35, dollars, col = cols, border = NA)
    for (i in seq_along(years)) {
      text(years[i], min(dollars[i] * 0.18, 12), sprintf("%.0f", dollars[i]),
           col = if (years[i] != 2026) "white" else "grey25", cex = 1.15, family = "Arial")
    }
    fy_ticks(); axis(2)
    box(bty = "u")
    # right axis: share of NIH
    usr <- par("usr")
    # overlay lines in dollar units (already *k)
    lines(years, D$CHD_pct_of_NIH * k, col = "black", lwd = 1.6, lty = 1)
    points(years, D$CHD_pct_of_NIH * k, pch = 16, col = "black", cex = 0.9)
    r <- D[!is.na(D$rcdc_pct_of_NIH), ]
    lines(r$FY, r$rcdc_pct_of_NIH * k, col = "black", lwd = 1.6, lty = 2)
    points(r$FY, r$rcdc_pct_of_NIH * k, pch = 22, bg = "white", col = "black", cex = 1.05, lwd = 1.2)
    at <- axTicks(2)
    axis(4, at = at, labels = sprintf("%.2f", at / k))
    mtext("% of all NIH funding", side = 4, line = 2.6, las = 0, family = "Arial")
    legend("top", inset = c(0, -0.14), xpd = NA, bty = "n", horiz = TRUE, cex = 0.95,
           legend = c("v2.4 combined", "NIH RCDC category"),
           lty = c(1, 2), lwd = 1.6, pch = c(16, 22), pt.bg = c("black", "white"),
           col = "black")
    cap <- paste0(
      "Bars: v2.4 combined (Tier 1 + Tier 2) CHD dollars, nominal. Lines: v2.4 combined share of all NIH funding (solid) ",
      "and the NIH RCDC \u201cCongenital Heart Disease\u201d share (dashed, FY2016\u20132025). *FY2026 partial (records through Oct 20, 2026), shown lighter."
    )
    mtext(paste(strwrap(cap, 118), collapse = "\n"), side = 1, line = 4.4, adj = 0, cex = 0.72, family = "Arial")
  })
}

fig2 <- function(age, out) {
  chd_with_device("Fig2_CHD_by_age_focus", out, 12, 7.5, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        mar = c(6.2, 4.2, 3.6, 1.4), oma = c(0, 0, 0.2, 0),
        cex.main = 1.35, cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.6, 0.6, 0))
    ymax <- age_ymax(age)
    plot(NA, xlim = c(2012.4, 2026.6), ylim = c(0, ymax * 1.08), axes = FALSE,
         xlab = "Fiscal year", ylab = "CHD funding, $ millions",
         main = "CHD funding by age focus")
    stacked_bars(age)
    fy_ticks(); axis(2); box(bty = "l")
    legend("top", inset = c(0, -0.14), xpd = NA, bty = "n", horiz = TRUE, cex = 0.95,
           legend = AGE_ORDER_V24, fill = AGE_COLORS_V24, border = NA)
    cap <- paste0(
      "v2.4 combined (Tier 1 + Tier 2) projects; age focus is the v2.4 4-level rule (Pediatric / Adult / Both / Not age-specific). ",
      "*FY2026 partial, shown lighter."
    )
    mtext(paste(strwrap(cap, 118), collapse = "\n"), side = 1, line = 4.4, adj = 0, cex = 0.72, family = "Arial")
  })
}

fig3 <- function(O, out) {
  chd_with_device("Fig3_keyword_vs_RCDC", out, 12, 7.5, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        mar = c(6.2, 4.2, 3.6, 1.4), oma = c(0, 0, 0.2, 0),
        cex.main = 1.25, cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.6, 0.6, 0))
    Oo <- O[!is.na(O$FY), ]
    years <- Oo$FY
    both <- Oo$both_M; only <- Oo$classifier_only_M; rcdc <- Oo$rcdc_only_M
    ytop <- max(both + only + rcdc) * 1.08
    plot(NA, xlim = c(2015.4, 2025.6), ylim = c(0, ytop), axes = FALSE,
         xlab = "Fiscal year", ylab = "$ millions",
         main = "v2.4 combined classifier vs NIH RCDC \u201cCongenital Heart Disease\u201d")
    rect(years - 0.35, 0, years + 0.35, both, col = "grey20", border = NA)
    rect(years - 0.35, both, years + 0.35, both + only, col = "grey60", border = NA)
    rect(years - 0.35, both + only, years + 0.35, both + only + rcdc, col = "grey88", border = NA)
    axis(1, at = 2016:2025); axis(2); box(bty = "l")
    legend("top", inset = c(0, -0.14), xpd = NA, bty = "n", horiz = TRUE, cex = 0.95,
           legend = c("Both definitions", "v2.4 combined only", "RCDC only"),
           fill = c("grey20", "grey60", "grey88"), border = NA)
    cap <- paste0(
      "FY2016\u20132025. Counts, dollars, and overlap percentages are in Overlap_v2.4_vs_RCDC. ",
      "RCDC-only dollars were mostly inherited arrhythmia, cardiomyopathy, valve, and heart-development grants in the v1 manual review."
    )
    mtext(paste(strwrap(cap, 118), collapse = "\n"), side = 1, line = 4.4, adj = 0, cex = 0.72, family = "Arial")
  })
}

dual_bar_share <- function(age_df, D, share_col, share_name, title, caption, stem, out,
                           width = 12, height = 7.5, title_loc = NULL) {
  chd_with_device(stem, out, width, height, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        mar = c(6.2, 4.2, 3.6, 4.4), oma = c(0, 0, 0.2, 0),
        cex.main = 1.25, cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.6, 0.6, 0))
    ymax <- age_ymax(age_df)
    pct <- D[[share_col]]
    k <- ymax * 1.15 / max(pct)
    ytop <- ymax * 1.30
    plot(NA, xlim = c(2012.4, 2026.6), ylim = c(0, ytop), axes = FALSE,
         xlab = "Fiscal year", ylab = "CHD funding, $ millions",
         main = title)
    stacked_bars(age_df)
    fy_ticks(); axis(2)
    box(bty = "u")
    lines(D$FY, pct * k, col = "black", lwd = 1.8)
    points(D$FY, pct * k, pch = 21, bg = "white", col = "black", cex = 1.1, lwd = 1.3)
    text(D$FY, pct * k + ymax * 0.025, sprintf("%.2f%%", pct),
         adj = c(0.5, 0), cex = 0.75, family = "Arial")
    at <- axTicks(2)
    axis(4, at = at, labels = sprintf("%.2f", at / k))
    mtext(share_name, side = 4, line = 2.6, las = 0, family = "Arial")
    legend("top", inset = c(0, -0.14), xpd = NA, bty = "n", horiz = TRUE, cex = 0.95,
           legend = AGE_ORDER_V24, fill = AGE_COLORS_V24, border = NA)
    mtext(paste(strwrap(caption, 118), collapse = "\n"), side = 1, line = 4.4, adj = 0, cex = 0.72, family = "Arial")
  })
}

# Two-panel helper used by Fig4-5 and the main figure. `draw` is called
# after par() has been set for the current panel.
draw_dual_panel <- function(age_df, D, share_col, share_name, title) {
  ymax <- age_ymax(age_df)
  pct <- D[[share_col]]
  k <- ymax * 1.15 / max(pct)
  ytop <- ymax * 1.30
  plot(NA, xlim = c(2012.4, 2026.6), ylim = c(0, ytop), axes = FALSE,
       xlab = "", ylab = "CHD funding, $ millions", main = "")
  title(main = title, adj = 0, cex.main = 1.15, line = 0.6, family = "Arial")
  stacked_bars(age_df)
  fy_ticks(); axis(2)
  box(bty = "u")
  lines(D$FY, pct * k, col = "black", lwd = 1.8)
  points(D$FY, pct * k, pch = 21, bg = "white", col = "black", cex = 1.1, lwd = 1.3)
  text(D$FY, pct * k + ymax * 0.025, sprintf("%.2f%%", pct),
       adj = c(0.5, 0), cex = 0.75, family = "Arial")
  at <- axTicks(2)
  axis(4, at = at, labels = sprintf("%.2f", at / k))
  mtext(share_name, side = 4, line = 2.6, las = 0, family = "Arial")
  invisible(NULL)
}

fig4_5_6 <- function(D, age_all, age_incvd, out) {
  cap_a <- paste0(
    "Bars: v2.4 combined CHD dollars by age focus, among projects that also meet the CVD definition. ",
    "Line: nested CHD as % of total NIH CVD funding. *FY2026 partial (records through Oct 20, 2026), shown lighter."
  )
  dual_bar_share(age_incvd, D, "CHD_pct_of_CVD", "CHD, % of NIH CVD funding",
                 "CHD funding relative to total NIH cardiovascular funding", cap_a, "Fig4_CHD_vs_CVD", out)
  cap_b <- paste0(
    "Bars: v2.4 combined CHD dollars by age focus (all combined projects). ",
    "Line: CHD as % of all NIH funding. *FY2026 partial (records through Oct 20, 2026), shown lighter."
  )
  dual_bar_share(age_all, D, "CHD_pct_of_NIH", "CHD, % of all NIH funding",
                 "CHD funding relative to total NIH funding", cap_b, "Fig5_CHD_vs_NIH", out)

  # Fig6
  chd_with_device("Fig6_CVD_vs_NIH_context", out, 12, 7.5, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        mar = c(6.2, 4.2, 3.6, 1.4), oma = c(0, 0, 0.2, 0),
        cex.main = 1.25, cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.6, 0.6, 0))
    years <- D$FY
    nih <- D$NIH_USD_B
    cvd <- D$CVD_USD_B
    ytop <- max(nih) * 1.10
    plot(NA, xlim = c(2012.4, 2026.6), ylim = c(0, ytop), axes = FALSE,
         xlab = "Fiscal year", ylab = "$ billions",
         main = "NIH cardiovascular funding within total NIH funding")
    rect(years - 0.35, 0, years + 0.35, ifelse(years != 2026, nih, 0), col = "grey80", border = NA)
    rect(years - 0.35, 0, years + 0.35, ifelse(years == 2026, nih, 0),
         col = adjustcolor("grey80", 0.5), border = NA)
    rect(years - 0.35, 0, years + 0.35, ifelse(years != 2026, cvd, 0), col = "grey25", border = NA)
    rect(years - 0.35, 0, years + 0.35, ifelse(years == 2026, cvd, 0),
         col = adjustcolor("grey25", 0.5), border = NA)
    text(years, cvd + 0.45, sprintf("%.1f%%", D$CVD_pct_of_NIH),
         adj = c(0.5, 0), cex = 0.85, family = "Arial")
    fy_ticks(); axis(2); box(bty = "l")
    legend("top", inset = c(0, -0.14), xpd = NA, bty = "n", horiz = TRUE, cex = 0.95,
           legend = c("All NIH", "Cardiovascular (CVD)"),
           fill = c("grey80", "grey25"), border = NA)
    mtext("Labels: CVD as % of all NIH funding. Denominators are unchanged from v1. *FY2026 partial.",
          side = 1, line = 4.4, adj = 0, cex = 0.72, family = "Arial")
  })

  # Two-panel Fig4-5 (stacked). Row 1 is a dedicated legend strip.
  chd_with_device("Fig4-5_CHD_vs_CVD_and_NIH_two_panel", out, 12, 13.5, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        oma = c(4.8, 0.4, 0.4, 0.4),
        cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.4, 0.55, 0))
    layout(matrix(1:3, ncol = 1), heights = c(0.16, 1.15, 1.0))
    par(mar = c(0, 4.4, 0.2, 4.4))
    plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))
    legend("center", bty = "n", horiz = TRUE, cex = 1.0, xpd = NA,
           legend = AGE_ORDER_V24, fill = AGE_COLORS_V24, border = NA)
    par(mar = c(3.0, 4.4, 2.2, 4.4))
    draw_dual_panel(age_incvd, D, "CHD_pct_of_CVD", "CHD, % of NIH CVD funding",
                    "A. CHD relative to total NIH CVD funding")
    par(mar = c(4.2, 4.4, 2.2, 4.4))
    draw_dual_panel(age_all, D, "CHD_pct_of_NIH", "CHD, % of all NIH funding",
                    "B. CHD relative to total NIH funding")
    mtext("Fiscal year", side = 1, line = 2.6, family = "Arial")
    cap <- paste0(
      "Bars: v2.4 combined CHD dollars by age focus (A: projects within the CVD definition; B: all combined projects). ",
      "Lines: CHD share. *FY2026 partial (records through Oct 20, 2026), shown lighter."
    )
    mtext(paste(strwrap(cap, 118), collapse = "\n"), side = 1, line = 3.4, adj = 0,
          cex = 0.72, family = "Arial", outer = TRUE)
  })
}

fig7 <- function(W, out) {
  chd_with_device("Fig7_CHD_deaths_vs_funding_share", out, 13, 8.5, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        oma = c(5.0, 0.4, 3.2, 0.4),
        cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.4, 0.55, 0))
    layout(matrix(1:2, ncol = 2), widths = c(1, 1))
    panels <- list(
      list(title = "CHD share of CVD deaths (I00\u2013I99 + Q20\u2013Q26)",
           series = list(
             list(lab = "CHD deaths, any mention", x = W$year, y = W$chd_any_pct_of_cvd_all,
                  lty = 1, col = "black", bg = "white"),
             list(lab = "CHD deaths, underlying cause", x = W$year, y = W$chd_ucd_pct_of_cvd_all,
                  lty = 2, col = "black", bg = "white"),
             list(lab = "CHD share of NIH CVD funding", x = W$year, y = W$CHD_pct_of_CVD_funding,
                  lty = 1, col = "#c0392b", bg = "#c0392b")
           )),
      list(title = "CHD share of heart-disease deaths (+ Q20\u2013Q26)",
           series = list(
             list(lab = "CHD deaths, any mention", x = W$year, y = W$chd_any_pct_of_heart_all,
                  lty = 1, col = "black", bg = "white"),
             list(lab = "CHD deaths, underlying cause", x = W$year, y = W$chd_ucd_pct_of_heart_all,
                  lty = 2, col = "black", bg = "white"),
             list(lab = "CHD share of NIH CVD funding", x = W$year, y = W$CHD_pct_of_CVD_funding,
                  lty = 1, col = "#c0392b", bg = "#c0392b")
           ))
    )
    for (i in seq_along(panels)) {
      par(mar = c(4.2, 4.2, 2.6, 0.8))
      p <- panels[[i]]
      ys <- unlist(lapply(p$series, function(s) s$y), use.names = FALSE)
      ytop <- max(ys, na.rm = TRUE) * 1.08
      plot(NA, xlim = c(2012.5, 2024.5), ylim = c(0, ytop), axes = FALSE,
           xlab = "Year (funding: fiscal year)", ylab = "Percent", main = "")
      title(main = p$title, cex.main = 1.05, line = 0.6, family = "Arial")
      for (s in p$series) {
        ok <- !is.na(s$y)
        lines(s$x[ok], s$y[ok], lty = s$lty, col = s$col, lwd = 1.6)
        points(s$x[ok], s$y[ok], pch = 21, bg = s$bg, col = s$col, cex = 1.0, lwd = 1.2)
      }
      axis(1, at = seq(2013, 2024, by = 2)); axis(2); box(bty = "l")
    }
    par(xpd = NA)
    legend("top", inset = c(0, -0.28), xpd = NA, bty = "n", horiz = TRUE, cex = 0.85,
           legend = c("CHD deaths, any mention", "CHD deaths, underlying cause", "CHD share of NIH CVD funding"),
           lty = c(1, 2, 1), lwd = 1.6,
           pch = 21, pt.bg = c("white", "white", "#c0392b"),
           col = c("black", "black", "#c0392b"))
    mtext("CHD share of cardiovascular deaths vs CHD share of NIH CVD funding, all ages",
          side = 3, line = 1.4, outer = TRUE, cex = 1.15, font = 2, family = "Arial")
    cap <- paste0(
      "Mortality: CDC WONDER final files (2013\u20132017 bridged-race D76/D77; 2018\u20132024 single-race D158/D157). ",
      "CHD = ICD-10 Q20\u2013Q26. Denominators = underlying-cause CVD (I00\u2013I99) or heart disease plus underlying-cause CHD. ",
      "The funding line is the v2.4 nested CHD share of NIH CVD funding (fiscal year aligned to calendar year). ",
      "The comparison is ecological and implies no causal relation. Death counts are unchanged from v1. ",
      "The shared percent axis follows the v1 figure (funding shares are larger than death shares)."
    )
    mtext(paste(strwrap(cap, 130), collapse = "\n"), side = 1, line = 3.4, adj = 0,
          cex = 0.70, family = "Arial", outer = TRUE)
  })
}

fig8 <- function(W, out) {
  chd_with_device("Fig8_CHD_deaths_share_by_age", out, 13, 8.0, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        oma = c(4.6, 0.4, 3.0, 0.4),
        cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.4, 0.55, 0))
    layout(matrix(1:2, ncol = 2))
    groups <- list(
      list(title = "Pediatric (<18 y)",
           series = list(list(lab = "Underlying cause", x = W$year, y = W$chd_ucd_pct_of_cvd_ped, lty = 2))),
      list(title = "Adult (18+ y)",
           series = list(
             list(lab = "Any mention", x = W$year, y = W$chd_any_pct_of_cvd_adult, lty = 1),
             list(lab = "Underlying cause", x = W$year, y = W$chd_ucd_pct_of_cvd_adult, lty = 2)
           ))
    )
    for (g in groups) {
      par(mar = c(4.2, 4.4, 2.4, 0.8))
      ys <- unlist(lapply(g$series, function(s) s$y), use.names = FALSE)
      ytop <- max(ys, na.rm = TRUE) * 1.12
      plot(NA, xlim = c(2012.5, 2024.5), ylim = c(0, ytop), axes = FALSE,
           xlab = "Year", ylab = "CHD deaths, % of CVD deaths in age group", main = "")
      title(main = g$title, cex.main = 1.15, line = 0.6, family = "Arial")
      for (s in g$series) {
        lines(s$x, s$y, col = "black", lwd = 1.6, lty = s$lty)
        points(s$x, s$y, pch = 21, bg = "white", col = "black", cex = 1.05, lwd = 1.2)
      }
      axis(1, at = seq(2013, 2024, by = 2)); axis(2); box(bty = "l")
      legend("topright", bty = "n", legend = vapply(g$series, `[[`, "", "lab"),
             lty = vapply(g$series, `[[`, 1, "lty"), lwd = 1.6, col = "black")
    }
    mtext("CHD share of cardiovascular deaths by age group",
          side = 3, line = 1.1, outer = TRUE, cex = 1.2, font = 2, family = "Arial")
    cap <- paste0(
      "Pediatric any-mention share is not shown: most such deaths have a non-CVD underlying cause, so the ratio is not a share (87\u201394%; in the workbook). ",
      "Death counts are unchanged from v1. Adult includes deaths with age not stated."
    )
    mtext(paste(strwrap(cap, 130), collapse = "\n"), side = 1, line = 3.0, adj = 0,
          cex = 0.70, family = "Arial", outer = TRUE)
  })
}

fig_main <- function(D, age_incvd, W, out) {
  chd_with_device("Fig_main_two_panel", out, 12, 13.5, also_tif = TRUE, expr = {
    par(family = "Arial", las = 1, xaxs = "i", yaxs = "i",
        oma = c(5.6, 0.4, 0.4, 0.4),
        cex.lab = 1.0, cex.axis = 0.95, tcl = -0.3, mgp = c(2.4, 0.55, 0))
    layout(matrix(1:3, ncol = 1), heights = c(0.16, 1.15, 1.0))
    par(mar = c(0, 4.6, 0.2, 4.4))
    plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))
    legend("center", bty = "n", horiz = TRUE, cex = 1.0, xpd = NA,
           legend = AGE_ORDER_V24, fill = AGE_COLORS_V24, border = NA)
    par(mar = c(3.6, 4.6, 2.2, 4.4))
    draw_dual_panel(age_incvd, D, "CHD_pct_of_CVD", "CHD, % of NIH CVD funding",
                    "A. CHD funding and share of NIH CVD funding")
    mtext("Fiscal year", side = 1, line = 2.4, family = "Arial")
    par(mar = c(4.4, 4.6, 2.2, 1.6))
    plot(NA, xlim = c(2012.5, 2024.5), ylim = c(0, 0.30), axes = FALSE,
         xlab = "Calendar year", ylab = "Adult CHD deaths, % of adult CVD deaths", main = "")
    title(main = "B. Adult CHD share of cardiovascular deaths", adj = 0, cex.main = 1.15,
          line = 0.6, family = "Arial")
    lines(W$year, W$chd_any_pct_of_cvd_adult, col = "black", lwd = 1.6, lty = 1)
    points(W$year, W$chd_any_pct_of_cvd_adult, pch = 21, bg = "white", col = "black", cex = 1.1, lwd = 1.2)
    lines(W$year, W$chd_ucd_pct_of_cvd_adult, col = "black", lwd = 1.6, lty = 2)
    points(W$year, W$chd_ucd_pct_of_cvd_adult, pch = 21, bg = "white", col = "black", cex = 1.1, lwd = 1.2)
    axis(1, at = 2013:2024)
    axis(2, at = seq(0, 0.30, by = 0.05), labels = sprintf("%.2f", seq(0, 0.30, by = 0.05)))
    box(bty = "l")
    legend("topleft", bty = "n", horiz = TRUE, cex = 0.95,
           legend = c("Any mention", "Underlying cause"), lty = c(1, 2), lwd = 1.6, col = "black")
    cap <- paste0(
      "A: Bars are v2.4 combined CHD dollars among projects that also meet the CVD definition, by age focus; ",
      "the line is their share of NIH CVD funding. *FY2026 partial (records through Oct 20, 2026), shown lighter. ",
      "B: Adult (18 years or older, including age not stated) deaths with CHD (ICD-10 Q20\u2013Q26) mentioned anywhere ",
      "on the death certificate (solid) or as the underlying cause (dashed), as a percentage of adult underlying-cause ",
      "CVD deaths (I00\u2013I99) plus underlying-cause CHD deaths. Mortality counts are unchanged from v1."
    )
    mtext(paste(strwrap(cap, 118), collapse = "\n"), side = 1, line = 3.6, adj = 0,
          cex = 0.70, family = "Arial", outer = TRUE)
  })
}

load_figure_tables <- function(out_dir) {
  cache <- file.path(out_dir, "_tables.rds")
  if (file.exists(cache)) return(readRDS(cache))
  xlsx <- file.path(out_dir, "chd_v2.4_shares_mortality.xlsx")
  if (!file.exists(xlsx)) stop("Missing _tables.rds and shares workbook in ", out_dir,
                               "; run R/26_v24_shares.R first.")
  if (!requireNamespace("readxl", quietly = TRUE)) stop("readxl is required to load the shares workbook")
  melt_age <- function(sheet) {
    w <- as.data.frame(readxl::read_excel(xlsx, sheet = sheet))
    tidyr::pivot_longer(w, cols = -"FY", names_to = "age", values_to = "USD_M")
  }
  list(
    D_v24 = as.data.frame(readxl::read_excel(xlsx, sheet = "Yearly_v2.4")),
    age_v24 = as.data.frame(melt_age("Age_USD_M_v2.4")),
    age_incvd = as.data.frame(melt_age("Age_in_CVD_USD_M_v2.4")),
    O_v24 = as.data.frame(readxl::read_excel(xlsx, sheet = "Overlap_v2.4_vs_RCDC")),
    W = as.data.frame(readxl::read_excel(xlsx, sheet = "Mortality_yearly"))
  )
}

run_v24_figures <- function(out_dir = "outputs/v2.4/figures_tables", tables = NULL) {
  if (is.null(tables)) tables <- load_figure_tables(out_dir)
  D <- tables$D_v24
  age <- if (!is.null(tables$age_v24)) tables$age_v24 else tables$age
  age_cv <- if (!is.null(tables$age_incvd)) tables$age_incvd else tables$age_incvd_v24
  O <- if (!is.null(tables$O_v24)) tables$O_v24 else tables$O
  W <- if (!is.null(tables$W)) tables$W else tables$W_v24
  fig1(D, out_dir)
  fig2(age, out_dir)
  fig3(O, out_dir)
  fig4_5_6(D, age, age_cv, out_dir)
  fig7(W, out_dir)
  fig8(W, out_dir)
  fig_main(D, age_cv, W, out_dir)
  cat("Wrote figures under ", out_dir, "\n", sep = "")
  invisible(TRUE)
}

if (identical(environment(), globalenv()) && !interactive() &&
    any(grepl("27_v24_figures\\.R$", commandArgs(trailingOnly = FALSE)))) {
  setwd(chd_root())
  run_v24_figures()
}
