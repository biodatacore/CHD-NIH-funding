#' 03_classify.R -- CHD definitions and the pediatric/adult split (rule-based, no language model).
#'
#' CHD definitions (per project-year):
#'   kw    (PRIMARY, all years) keyword classifier on title + pooled abstract/PHR text:
#'           >= 1 strong CHD term in the title
#'        OR >= 3 strong CHD term mentions in the text
#'        OR  2 strong mentions AND >= 2 weak CHD mentions
#'        OR >= 1 strong mention AND a pediatric-cardiac title ("pediatric heart ...", or a
#'           pediatric term plus heart/cardi- in the title, eg "infant cardiopulmonary bypass")
#'   rcdc  NIH RCDC category "Congenital Heart Disease" (exists FY2016-2025 only: the category
#'         starts in FY2016 and FY2026 is not yet categorized)
#'   union kw OR rcdc (sensitivity; FY2016-2025)
#' Age group (applied to CHD projects; human-population terms only, see terms.R):
#'   ped = pediatric term in title (incl. "pediatric heart ...") OR >= 2 pediatric mentions
#'   adu = adult-CHD term in title OR >= 2 adult-population mentions
#   Basic / non-age-specific (checked FIRST) no age term in the title, >= 3 basic-science
#'             mentions and more basic-science than human/clinical mentions (HUMAN in terms.R);
#'             such grants often cite "1% of live births" as motivation, which is not an age focus
#'   Both      ped & adu, OR an explicit both-ages phrase ("children and adults", "from
#'             childhood into adulthood") together with ped or adu
#'   Pediatric ped only;  Adult  adu only
#'   Basic / non-age-specific  also: neither ped nor adu, no age term in title, >= 3
#'             basic-science mentions (animal models, embryos, iPSC, developmental pathways)
#'   Unclear   everything else (eg, registries/devices/genetics with no stated age group)
#' Output: data/work/C.rds (G plus flags), data/work/rules.txt
source("R/00_setup.R")
G <- readRDS(wp("G.rds"))
# Recompute t_cardi from the title when a title is present. Shipped G.rds
# already carries t_cardi for the full universe (titles are shipped only for
# CHD-signal candidates, to avoid investigator names in supplement titles).
if (!"t_cardi" %in% names(G)) {
  G[, t_cardi := hit(title, "(heart|cardi)")]
} else if ("title" %in% names(G)) {
  has <- !is.na(G$title) & nzchar(G$title)
  if (any(has)) G[has, t_cardi := hit(title, "(heart|cardi)")]
}
G[, kw := t_str >= 1 | s_str >= 3 | (s_str >= 2 & s_weak >= 2) | (s_str >= 1 & (t_pedcard | (t_ped & t_cardi)))]
G[, rcdc_avail := FY %in% 2016:2025]
G[, union := kw | (rcdc & rcdc_avail)]
G[, ped := t_ped | t_pedcard | s_ped >= 2]
G[, adu := t_adu | s_adu >= 2]
# mechanistic work: no age term in the title and basic-science terms outnumber clinical ones
G[, basic_dom := !t_ped & !t_adu & !t_pedcard & s_basic >= 3 & s_basic > s_hum]
G[, age := fcase(
  basic_dom, "Basic/non-age-specific",
  (ped & adu) | (s_life >= 1 & (ped | adu)), "Both",
  ped, "Pediatric",
  adu, "Adult",
  !t_ped & !t_adu & s_basic >= 3, "Basic/non-age-specific",
  default = "Unclear")]
G[, age := factor(age, levels = c("Pediatric", "Adult", "Both", "Basic/non-age-specific", "Unclear"))]
saveRDS(G, wp("C.rds"))
x <- G[kw == TRUE]
say("keyword CHD project-years: ", nrow(x), "; age split: ", paste(names(table(x$age)), table(x$age), collapse = ", "))
