#!/usr/bin/env python3
"""
v2.4 figures for the CHD funding, share, and mortality tables.

Style follows the v1 ggplot2 scripts (R/06_figures.R, R/07_cvd.R, R/08_wonder.R,
and the two-panel main figure): Arial, no grid, color only for age
groups, FY2026 drawn lighter and labelled 2026*.

Writes PNG/PDF (and LZW TIF for the two-panel main figure) into this folder only,
at 300 dpi, under outputs/v2.4/figures_tables/. Does not overwrite other outputs.
"""
from __future__ import annotations

import argparse
import textwrap
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from matplotlib.ticker import FuncFormatter
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "outputs" / "v2.4" / "figures_tables"
FONT_CANDIDATES = [
    Path("/home/box/.fonts/arial"),
    Path("/usr/share/fonts/truetype/msttcorefonts"),
    Path("/usr/share/fonts/truetype/arial"),
    Path.home() / ".fonts" / "arial",
]
DPI = 300

FONT_DIR = next((p for p in FONT_CANDIDATES if (p / "arial.ttf").exists() or (p / "Arial.ttf").exists()), None)
if FONT_DIR is not None:
    for fn in ("arial.ttf", "Arial.ttf", "arialbd.ttf", "Arialbd.ttf", "ariali.ttf", "arialbi.ttf"):
        fp = FONT_DIR / fn
        if fp.exists():
            font_manager.fontManager.addfont(str(fp))

mpl.rcParams.update({
    "font.family": "Arial",
    "font.size": 16,
    "axes.titlesize": 17,
    "axes.titleweight": "bold",
    "axes.labelsize": 15,
    "xtick.labelsize": 13,
    "ytick.labelsize": 13,
    "legend.fontsize": 12,
    "legend.frameon": False,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": False,
    "axes.edgecolor": "black",
    "axes.labelcolor": "black",
    "xtick.color": "black",
    "ytick.color": "black",
    "text.color": "black",
    "figure.facecolor": "white",
    "axes.facecolor": "white",
    "savefig.dpi": DPI,
    "savefig.facecolor": "white",
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
})

AGE_COLORS_V24 = {
    "Pediatric": "#1f5fa8",
    "Adult": "#c0392b",
    "Both": "#7b4fa0",
    "Not age-specific": "0.45",
}
AGE_ORDER_V24 = ["Pediatric", "Adult", "Both", "Not age-specific"]


def classic(ax, right_spine=False):
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(right_spine)
    ax.spines["left"].set_color("black")
    ax.spines["bottom"].set_color("black")
    ax.tick_params(colors="black", direction="out")
    ax.set_axisbelow(True)


def fy_ticks(ax, years=range(2013, 2027)):
    ax.set_xticks(list(years))
    ax.set_xticklabels(["2026*" if y == 2026 else str(y) for y in years], rotation=0)


def add_caption(fig, text, width=118):
    wrapped = "\n".join(textwrap.wrap(text, width=width))
    fig.text(0.08, 0.015, wrapped, ha="left", va="bottom", fontsize=10, fontname="Arial")


def save_fig(fig, stem, out: Path, also_tif=False, also_pdf=True):
    png = out / f"{stem}.png"
    pdf_meta = {"Title": stem, "Author": "CHD pipeline", "Creator": "CHD pipeline", "Producer": "CHD pipeline"}
    fig.savefig(png, dpi=DPI, bbox_inches="tight", pad_inches=0.2)
    # matplotlib writes dpi as 299.9994; stamp an exact 300 in the file header
    img = Image.open(png)
    img.save(png, dpi=(DPI, DPI))
    if also_pdf:
        fig.savefig(out / f"{stem}.pdf", dpi=DPI, bbox_inches="tight", pad_inches=0.2, metadata=pdf_meta)
    if also_tif:
        img.save(out / f"{stem}.tif", compression="tiff_lzw", dpi=(DPI, DPI))
    plt.close(fig)
    return png


def stacked_bars(ax, age_df, age_order, colors, value="USD_M"):
    years = list(range(2013, 2027))
    bottoms = {fy: 0.0 for fy in years}
    for age in age_order:
        sub = age_df[age_df["age"] == age].set_index("FY")[value]
        complete, y2026, bot = [], [], []
        for fy in years:
            h = float(sub.loc[fy]) if fy in sub.index else 0.0
            complete.append(h if fy != 2026 else 0.0)
            y2026.append(h if fy == 2026 else 0.0)
            bot.append(bottoms[fy])
            bottoms[fy] += h
        ax.bar(years, complete, bottom=bot, width=0.7, color=colors[age], edgecolor="none", label=age)
        ax.bar(years, y2026, bottom=bot, width=0.7, color=colors[age], edgecolor="none", alpha=0.45, label="_nolegend_")
    handles = [Patch(facecolor=colors[age], edgecolor="none", label=age) for age in age_order]
    return handles, max(bottoms.values()) if bottoms else 0


def layout_single(fig, top=0.86, right=0.88):
    fig.subplots_adjust(left=0.10, right=right, bottom=0.20, top=top)


def fig1(D, out):
    fig, ax = plt.subplots(figsize=(12, 7.5))
    classic(ax, right_spine=True)
    years = D["FY"].to_numpy()
    dollars = D["CHD_USD_M"].to_numpy()
    colors = ["0.55" if fy != 2026 else "0.85" for fy in years]
    ax.bar(years, dollars, width=0.7, color=colors, edgecolor="none")
    for fy, v in zip(years, dollars):
        ax.text(fy, min(v * 0.18, 12), f"{v:.0f}", ha="center", va="center",
                color="white" if fy != 2026 else "0.25", fontsize=13, fontname="Arial")
    k = dollars.max() / max(D["CHD_pct_of_NIH"].max(), D["rcdc_pct_of_NIH"].dropna().max()) * 0.92
    ax2 = ax.twinx()
    classic(ax2, right_spine=True)
    ax2.spines["left"].set_visible(False)
    ax2.plot(years, D["CHD_pct_of_NIH"] * k, color="black", lw=1.6, ls="-")
    ax2.scatter(years, D["CHD_pct_of_NIH"] * k, s=40, color="black", zorder=3)
    r = D.dropna(subset=["rcdc_pct_of_NIH"])
    ax2.plot(r["FY"], r["rcdc_pct_of_NIH"] * k, color="black", lw=1.6, ls="--")
    ax2.scatter(r["FY"], r["rcdc_pct_of_NIH"] * k, s=45, facecolor="white", edgecolor="black",
                linewidth=1.2, zorder=3, marker="s")
    ax.set_ylim(0, dollars.max() * 1.08)
    ax2.set_ylim(0, dollars.max() * 1.08)
    ax2.yaxis.set_major_formatter(FuncFormatter(lambda y, p: f"{y/k:.2f}"))
    ax.set_ylabel("CHD funding, $ millions")
    ax2.set_ylabel("% of all NIH funding")
    ax.set_xlabel("Fiscal year")
    fy_ticks(ax)
    ax.set_xlim(2012.4, 2026.6)
    ax.set_title("NIH funding for congenital heart disease research", pad=28)
    handles = [
        Line2D([0], [0], color="black", lw=1.6, label="v2.4 combined"),
        Line2D([0], [0], color="black", lw=1.6, ls="--", marker="s", markerfacecolor="white",
               markeredgecolor="black", label="NIH RCDC category"),
    ]
    fig.legend(handles=handles, loc="upper center", ncol=2, bbox_to_anchor=(0.5, 0.98), frameon=False)
    cap = ("Bars: v2.4 combined (Tier 1 + Tier 2) CHD dollars, nominal. Lines: v2.4 combined share of all NIH funding (solid) "
           "and the NIH RCDC “Congenital Heart Disease” share (dashed, FY2016–2025). *FY2026 partial (records through Oct 20, 2026), shown lighter.")
    add_caption(fig, cap)
    layout_single(fig)
    save_fig(fig, "Fig1_CHD_dollars_and_share", out)


def fig2(age, out):
    fig, ax = plt.subplots(figsize=(12, 7.5))
    classic(ax)
    handles, ymax = stacked_bars(ax, age, AGE_ORDER_V24, AGE_COLORS_V24)
    ax.set_ylim(0, ymax * 1.08)
    fy_ticks(ax)
    ax.set_xlim(2012.4, 2026.6)
    ax.set_ylabel("CHD funding, $ millions")
    ax.set_xlabel("Fiscal year")
    ax.set_title("CHD funding by age focus", pad=28)
    fig.legend(handles=handles, loc="upper center", ncol=4, bbox_to_anchor=(0.5, 0.98), frameon=False)
    cap = ("v2.4 combined (Tier 1 + Tier 2) projects; age focus is the v2.4 4-level rule (Pediatric / Adult / Both / Not age-specific). "
           "*FY2026 partial, shown lighter.")
    add_caption(fig, cap)
    layout_single(fig, right=0.96)
    save_fig(fig, "Fig2_CHD_by_age_focus", out)


def fig3(O, out):
    O = O.dropna(subset=["FY"]).copy()
    fig, ax = plt.subplots(figsize=(12, 7.5))
    classic(ax)
    years = O["FY"].to_numpy()
    both = O["both_M"].to_numpy()
    only = O["classifier_only_M"].to_numpy()
    rcdc = O["rcdc_only_M"].to_numpy()
    ax.bar(years, both, width=0.7, color="0.20", label="Both definitions")
    ax.bar(years, only, width=0.7, bottom=both, color="0.60", label="v2.4 combined only")
    ax.bar(years, rcdc, width=0.7, bottom=both + only, color="0.88", label="RCDC only")
    ax.set_xticks(list(range(2016, 2026)))
    ax.set_xlim(2015.4, 2025.6)
    ax.set_ylabel("$ millions")
    ax.set_xlabel("Fiscal year")
    ax.set_ylim(0, (both + only + rcdc).max() * 1.08)
    ax.set_title("v2.4 combined classifier vs NIH RCDC “Congenital Heart Disease”", pad=28)
    handles = [
        Patch(facecolor="0.20", label="Both definitions"),
        Patch(facecolor="0.60", label="v2.4 combined only"),
        Patch(facecolor="0.88", label="RCDC only"),
    ]
    fig.legend(handles=handles, loc="upper center", ncol=3, bbox_to_anchor=(0.5, 0.98), frameon=False)
    cap = ("FY2016–2025. Counts, dollars, and overlap percentages are in Overlap_v2.4_vs_RCDC. "
           "RCDC-only dollars were mostly inherited arrhythmia, cardiomyopathy, valve, and heart-development grants in the v1 manual review.")
    add_caption(fig, cap)
    layout_single(fig, right=0.96)
    save_fig(fig, "Fig3_keyword_vs_RCDC", out)


def dual_bar_share(age_df, D, share_col, share_name, title, caption, stem, out):
    fig, ax = plt.subplots(figsize=(12, 7.5))
    classic(ax, right_spine=True)
    handles, ymax = stacked_bars(ax, age_df, AGE_ORDER_V24, AGE_COLORS_V24)
    pct = D[share_col].to_numpy()
    k = ymax * 1.15 / pct.max()
    ax2 = ax.twinx()
    classic(ax2, right_spine=True)
    ax2.spines["left"].set_visible(False)
    ax2.plot(D["FY"], D[share_col] * k, color="black", lw=1.8)
    ax2.scatter(D["FY"], D[share_col] * k, s=50, facecolor="white", edgecolor="black", linewidth=1.3, zorder=3)
    for fy, v in zip(D["FY"], D[share_col]):
        ax2.text(fy, v * k + ymax * 0.025, f"{v:.2f}%", ha="center", va="bottom", fontsize=9, fontname="Arial")
    ytop = ymax * 1.30
    ax.set_ylim(0, ytop)
    ax2.set_ylim(0, ytop)
    ax2.yaxis.set_major_formatter(FuncFormatter(lambda y, p: f"{y/k:.2f}"))
    ax.set_ylabel("CHD funding, $ millions")
    ax2.set_ylabel(share_name)
    ax.set_xlabel("Fiscal year")
    fy_ticks(ax)
    ax.set_xlim(2012.4, 2026.6)
    ax.set_title(title, pad=28)
    fig.legend(handles=handles, loc="upper center", ncol=4, bbox_to_anchor=(0.5, 0.98), frameon=False)
    add_caption(fig, caption)
    layout_single(fig, right=0.88)
    save_fig(fig, stem, out)


def fig4_5_6(D, age_all, age_incvd, out):
    cap_a = ("Bars: v2.4 combined CHD dollars by age focus, among projects that also meet the CVD definition. "
             "Line: nested CHD as % of total NIH CVD funding. *FY2026 partial (records through Oct 20, 2026), shown lighter.")
    dual_bar_share(age_incvd, D, "CHD_pct_of_CVD", "CHD, % of NIH CVD funding",
                   "CHD funding relative to total NIH cardiovascular funding", cap_a, "Fig4_CHD_vs_CVD", out)

    cap_b = ("Bars: v2.4 combined CHD dollars by age focus (all combined projects). "
             "Line: CHD as % of all NIH funding. *FY2026 partial (records through Oct 20, 2026), shown lighter.")
    dual_bar_share(age_all, D, "CHD_pct_of_NIH", "CHD, % of all NIH funding",
                   "CHD funding relative to total NIH funding", cap_b, "Fig5_CHD_vs_NIH", out)

    fig, ax = plt.subplots(figsize=(12, 7.5))
    classic(ax)
    years = D["FY"].to_numpy()
    nih = D["NIH_USD_B"].to_numpy()
    cvd = D["CVD_USD_B"].to_numpy()
    ax.bar(years, [v if fy != 2026 else 0 for fy, v in zip(years, nih)], width=0.7, color="0.80", label="All NIH")
    ax.bar(years, [v if fy == 2026 else 0 for fy, v in zip(years, nih)], width=0.7, color="0.80", alpha=0.5, label="_nolegend_")
    ax.bar(years, [v if fy != 2026 else 0 for fy, v in zip(years, cvd)], width=0.7, color="0.25", label="Cardiovascular (CVD)")
    ax.bar(years, [v if fy == 2026 else 0 for fy, v in zip(years, cvd)], width=0.7, color="0.25", alpha=0.5, label="_nolegend_")
    for fy, v, pct in zip(years, cvd, D["CVD_pct_of_NIH"]):
        ax.text(fy, v + 0.45, f"{pct:.1f}%", ha="center", va="bottom", fontsize=10, fontname="Arial")
    ax.set_ylim(0, nih.max() * 1.10)
    fy_ticks(ax)
    ax.set_xlim(2012.4, 2026.6)
    ax.set_ylabel("$ billions")
    ax.set_xlabel("Fiscal year")
    ax.set_title("NIH cardiovascular funding within total NIH funding", pad=28)
    handles = [Patch(facecolor="0.80", label="All NIH"), Patch(facecolor="0.25", label="Cardiovascular (CVD)")]
    fig.legend(handles=handles, loc="upper center", ncol=2, bbox_to_anchor=(0.5, 0.98), frameon=False)
    add_caption(fig, "Labels: CVD as % of all NIH funding. Denominators are unchanged from v1. *FY2026 partial.")
    layout_single(fig, right=0.96)
    save_fig(fig, "Fig6_CVD_vs_NIH_context", out)

    # two-panel Fig4-5
    fig = plt.figure(figsize=(12, 13.5))
    gs = fig.add_gridspec(2, 1, height_ratios=[1.15, 1.0], hspace=0.38)
    ax1 = fig.add_subplot(gs[0])
    ax2 = fig.add_subplot(gs[1])
    handles = None
    for ax, age_df, share_col, ylab2, title in (
        (ax1, age_incvd, "CHD_pct_of_CVD", "CHD, % of NIH CVD funding", "A. CHD relative to total NIH CVD funding"),
        (ax2, age_all, "CHD_pct_of_NIH", "CHD, % of all NIH funding", "B. CHD relative to total NIH funding"),
    ):
        classic(ax, right_spine=True)
        handles, ymax = stacked_bars(ax, age_df, AGE_ORDER_V24, AGE_COLORS_V24)
        pct = D[share_col].to_numpy()
        k = ymax * 1.15 / pct.max()
        ax_r = ax.twinx()
        classic(ax_r, right_spine=True)
        ax_r.spines["left"].set_visible(False)
        ax_r.plot(D["FY"], D[share_col] * k, color="black", lw=1.8)
        ax_r.scatter(D["FY"], D[share_col] * k, s=50, facecolor="white", edgecolor="black", linewidth=1.3, zorder=3)
        for fy, v in zip(D["FY"], D[share_col]):
            ax_r.text(fy, v * k + ymax * 0.025, f"{v:.2f}%", ha="center", va="bottom", fontsize=9, fontname="Arial")
        ytop = ymax * 1.30
        ax.set_ylim(0, ytop)
        ax_r.set_ylim(0, ytop)
        ax_r.yaxis.set_major_formatter(FuncFormatter(lambda y, p, k=k: f"{y/k:.2f}"))
        ax.set_ylabel("CHD funding, $ millions")
        ax_r.set_ylabel(ylab2)
        fy_ticks(ax)
        ax.set_xlim(2012.4, 2026.6)
        ax.set_title(title, loc="left", pad=8)
    ax2.set_xlabel("Fiscal year")
    fig.legend(handles=handles, loc="upper center", ncol=4, bbox_to_anchor=(0.5, 0.99), frameon=False)
    cap = ("Bars: v2.4 combined CHD dollars by age focus (A: projects within the CVD definition; B: all combined projects). "
           "Lines: CHD share. *FY2026 partial (records through Oct 20, 2026), shown lighter.")
    add_caption(fig, cap)
    fig.subplots_adjust(left=0.10, right=0.88, top=0.93, bottom=0.10)
    save_fig(fig, "Fig4-5_CHD_vs_CVD_and_NIH_two_panel", out)


def fig7(W, out):
    fig, axes = plt.subplots(1, 2, figsize=(13, 8.5), sharey=False)
    panels = [
        ("CHD share of CVD deaths (I00–I99 + Q20–Q26)",
         [("CHD deaths, any mention", W["year"], W["chd_any_pct_of_cvd_all"], "solid", "black", "white"),
          ("CHD deaths, underlying cause", W["year"], W["chd_ucd_pct_of_cvd_all"], (0, (2, 2)), "black", "white"),
          ("CHD share of NIH CVD funding", W["year"], W["CHD_pct_of_CVD_funding"], "solid", "#c0392b", "#c0392b")]),
        ("CHD share of heart-disease deaths (+ Q20–Q26)",
         [("CHD deaths, any mention", W["year"], W["chd_any_pct_of_cvd_all"]*np.nan, "solid", "black", "white"),  # placeholder
          ]),
    ]
    # rebuild second panel properly (don't use the nan hack)
    panels = [
        ("CHD share of CVD deaths (I00–I99 + Q20–Q26)",
         [("CHD deaths, any mention", W["year"], W["chd_any_pct_of_cvd_all"], "solid", "black", "white"),
          ("CHD deaths, underlying cause", W["year"], W["chd_ucd_pct_of_cvd_all"], (0, (2, 2)), "black", "white"),
          ("CHD share of NIH CVD funding", W["year"], W["CHD_pct_of_CVD_funding"], "solid", "#c0392b", "#c0392b")]),
        ("CHD share of heart-disease deaths (+ Q20–Q26)",
         [("CHD deaths, any mention", W["year"], W["chd_any_pct_of_heart_all"], "solid", "black", "white"),
          ("CHD deaths, underlying cause", W["year"], W["chd_ucd_pct_of_heart_all"], (0, (2, 2)), "black", "white"),
          ("CHD share of NIH CVD funding", W["year"], W["CHD_pct_of_CVD_funding"], "solid", "#c0392b", "#c0392b")]),
    ]
    for ax, (title, series) in zip(axes, panels):
        classic(ax)
        for lab, x, y, ls, color, face in series:
            mask = y.notna()
            ax.plot(x[mask], y[mask], ls=ls, color=color, lw=1.6, label=lab)
            ax.scatter(x[mask], y[mask], s=42, facecolor=face, edgecolor=color, linewidth=1.2, zorder=3)
        ax.set_title(title, fontsize=13, pad=8)
        ax.set_xticks(list(range(2013, 2025, 2)))
        ax.set_xlim(2012.5, 2024.5)
        ax.set_ylim(0, None)
        ax.set_xlabel("Year (funding: fiscal year)")
        ax.set_ylabel("Percent")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.5, 0.99))
    fig.suptitle("CHD share of cardiovascular deaths vs CHD share of NIH CVD funding, all ages",
                 fontweight="bold", y=1.0, fontsize=15)
    cap = ("Mortality: CDC WONDER final files (2013–2017 bridged-race D76/D77; 2018–2024 single-race D158/D157). "
           "CHD = ICD-10 Q20–Q26. Denominators = underlying-cause CVD (I00–I99) or heart disease plus underlying-cause CHD. "
           "The funding line is the v2.4 nested CHD share of NIH CVD funding (fiscal year aligned to calendar year). "
           "The comparison is ecological and implies no causal relation. Death counts are unchanged from v1. "
           "The shared percent axis follows the v1 figure (funding shares are larger than death shares).")
    add_caption(fig, cap, width=130)
    fig.subplots_adjust(left=0.08, right=0.98, top=0.84, bottom=0.18, wspace=0.28)
    save_fig(fig, "Fig7_CHD_deaths_vs_funding_share", out)


def fig8(W, out):
    fig, axes = plt.subplots(1, 2, figsize=(13, 8.0))
    groups = [
        ("Pediatric (<18 y)",
         [("Underlying cause", W["year"], W["chd_ucd_pct_of_cvd_ped"], (0, (2, 2)))]),
        ("Adult (18+ y)",
         [("Any mention", W["year"], W["chd_any_pct_of_cvd_adult"], "solid"),
          ("Underlying cause", W["year"], W["chd_ucd_pct_of_cvd_adult"], (0, (2, 2)))]),
    ]
    for ax, (title, series) in zip(axes, groups):
        classic(ax)
        for lab, x, y, ls in series:
            ax.plot(x, y, color="black", lw=1.6, ls=ls, label=lab)
            ax.scatter(x, y, s=45, facecolor="white", edgecolor="black", linewidth=1.2, zorder=3)
        ax.set_title(title, pad=8)
        ax.set_xticks(list(range(2013, 2025, 2)))
        ax.set_xlim(2012.5, 2024.5)
        ax.set_ylim(bottom=0)
        ax.set_xlabel("Year")
        ax.set_ylabel("CHD deaths, % of CVD deaths in age group")
        ax.legend(loc="best", frameon=False)
    fig.suptitle("CHD share of cardiovascular deaths by age group", fontweight="bold", y=0.98, fontsize=16)
    cap = ("Pediatric any-mention share is not shown: most such deaths have a non-CVD underlying cause, so the ratio is not a share (87–94%; in the workbook). "
           "Death counts are unchanged from v1. Adult includes deaths with age not stated.")
    add_caption(fig, cap, width=130)
    fig.subplots_adjust(left=0.08, right=0.98, top=0.86, bottom=0.16, wspace=0.28)
    save_fig(fig, "Fig8_CHD_deaths_share_by_age", out)


def fig_main(D, age_incvd, W, out):
    """Two-panel main figure: A funding + CVD share; B adult death share. 12 x 13.5 in, 300 dpi, PNG+TIF."""
    fig = plt.figure(figsize=(12, 13.5))
    gs = fig.add_gridspec(2, 1, height_ratios=[1.15, 1.0], hspace=0.34)
    axA = fig.add_subplot(gs[0])
    classic(axA, right_spine=True)
    handles, ymax = stacked_bars(axA, age_incvd, AGE_ORDER_V24, AGE_COLORS_V24)
    pct = D["CHD_pct_of_CVD"].to_numpy()
    k = ymax * 1.15 / pct.max()
    axAr = axA.twinx()
    classic(axAr, right_spine=True)
    axAr.spines["left"].set_visible(False)
    axAr.plot(D["FY"], D["CHD_pct_of_CVD"] * k, color="black", lw=1.8)
    axAr.scatter(D["FY"], D["CHD_pct_of_CVD"] * k, s=50, facecolor="white", edgecolor="black", linewidth=1.3, zorder=3)
    for fy, v in zip(D["FY"], D["CHD_pct_of_CVD"]):
        axAr.text(fy, v * k + ymax * 0.025, f"{v:.2f}%", ha="center", va="bottom", fontsize=9, fontname="Arial")
    ytop = ymax * 1.30
    axA.set_ylim(0, ytop)
    axAr.set_ylim(0, ytop)
    axAr.yaxis.set_major_formatter(FuncFormatter(lambda y, p, k=k: f"{y/k:.2f}"))
    axA.set_ylabel("CHD funding, $ millions")
    axAr.set_ylabel("CHD, % of NIH CVD funding")
    fy_ticks(axA)
    axA.set_xlim(2012.4, 2026.6)
    axA.set_title("A. CHD funding and share of NIH CVD funding", loc="left", pad=8)
    axA.set_xlabel("Fiscal year")

    axB = fig.add_subplot(gs[1])
    classic(axB)
    axB.plot(W["year"], W["chd_any_pct_of_cvd_adult"], color="black", lw=1.6, ls="solid", label="Any mention")
    axB.scatter(W["year"], W["chd_any_pct_of_cvd_adult"], s=50, facecolor="white", edgecolor="black", linewidth=1.2, zorder=3)
    axB.plot(W["year"], W["chd_ucd_pct_of_cvd_adult"], color="black", lw=1.6, ls=(0, (2, 2)), label="Underlying cause")
    axB.scatter(W["year"], W["chd_ucd_pct_of_cvd_adult"], s=50, facecolor="white", edgecolor="black", linewidth=1.2, zorder=3)
    axB.set_xticks(list(range(2013, 2025)))
    axB.set_xlim(2012.5, 2024.5)
    axB.set_ylim(0, 0.30)
    axB.set_ylabel("Adult CHD deaths, % of adult CVD deaths")
    axB.set_xlabel("Calendar year")
    axB.set_title("B. Adult CHD share of cardiovascular deaths", loc="left", pad=8)
    axB.legend(loc="upper left", ncol=2, frameon=False)
    axB.yaxis.set_major_formatter(FuncFormatter(lambda y, p: f"{y:.2f}"))

    fig.legend(handles=handles, loc="upper center", ncol=4, bbox_to_anchor=(0.5, 0.99), frameon=False)
    cap = ("A: Bars are v2.4 combined CHD dollars among projects that also meet the CVD definition, by age focus; "
           "the line is their share of NIH CVD funding. *FY2026 partial (records through Oct 20, 2026), shown lighter. "
           "B: Adult (18 years or older, including age not stated) deaths with CHD (ICD-10 Q20–Q26) mentioned anywhere "
           "on the death certificate (solid) or as the underlying cause (dashed), as a percentage of adult underlying-cause "
           "CVD deaths (I00–I99) plus underlying-cause CHD deaths. Mortality counts are unchanged from v1.")
    add_caption(fig, cap, width=118)
    fig.subplots_adjust(left=0.11, right=0.88, top=0.93, bottom=0.11)
    save_fig(fig, "Fig_main_two_panel", out, also_tif=True)


def report_dpi(out: Path):
    print("Figure files (pixel size and dpi from the file header):")
    for p in sorted(out.glob("Fig*.png")) + sorted(out.glob("Fig*.tif")):
        im = Image.open(p)
        dpi = im.info.get("dpi")
        print(f"  {p.name}: {im.size[0]} x {im.size[1]} px, mode={im.mode}, dpi={dpi}")


def load_tables(out: Path):
    cache = out / "_tables.pkl"
    if cache.exists():
        return pd.read_pickle(cache)
    xlsx = out / "chd_v2.4_shares_mortality.xlsx"
    if not xlsx.exists():
        raise SystemExit(f"Missing {cache} and {xlsx}; run python3 R/21_v24_shares.py first.")
    def melt_age(sheet):
        w = pd.read_excel(xlsx, sheet)
        return w.melt(id_vars=["FY"], var_name="age", value_name="USD_M")
    return {
        "D_v24": pd.read_excel(xlsx, "Yearly_v2.4"),
        "age_v24": melt_age("Age_USD_M_v2.4"),
        "age_incvd_v24": melt_age("Age_in_CVD_USD_M_v2.4"),
        "O_v24": pd.read_excel(xlsx, "Overlap_v2.4_vs_RCDC"),
        "W_v24": pd.read_excel(xlsx, "Mortality_yearly"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()
    out = Path(args.out)
    T = load_tables(out)
    D = T["D_v24"]
    fig1(D, out)
    fig2(T["age_v24"], out)
    fig3(T["O_v24"], out)
    fig4_5_6(D, T["age_v24"], T["age_incvd_v24"], out)
    fig7(T["W_v24"], out)
    fig8(T["W_v24"], out)
    fig_main(D, T["age_incvd_v24"], T["W_v24"], out)
    print("Wrote figures to", out)
    report_dpi(out)


if __name__ == "__main__":
    main()
