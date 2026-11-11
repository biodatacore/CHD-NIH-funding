#' 02_build.R -- NIH project universe (denominator) and CHD/age features per project-year.
#'
#' Universe and dollars are IDENTICAL to the WHR pipeline (nih-womens-cv-funding):
#'   * one record per FULL_PROJECT_NUM per fiscal year (proj_{FY}.rds from WHR R/02_build.R);
#'   * dollars = parent-row TOTAL_COST, else the sum of component TOTAL_COST_SUB_PROJECT
#'     (component costs are already inside the parent's total, so rows are never summed);
#'   * administering IC must be an NIH Institute/Center (NIH_ICS);
#'   * FY2020/FY2024 intramural projects are replaced by versions with RePORTER-API text.
#' Added here, per project: RCDC "Congenital Heart Disease" flag (any row of the project
#' carries the category; FY2023 from the RePORTER API because the bulk file lacks RCDC), NIH
#' project terms, and keyword counts for CHD and age groups (terms.R).
#' Output: data/work/G.rds (one row per FY x project; no investigator fields)
source("R/00_setup.R"); source("R/terms.R")
lower_na <- function(x) { x <- tolower(x); x[is.na(x)] <- ""; x }

API <- readRDS(wp("api_rcdc_chd.rds"))

build_year <- function(fy) {
  P <- readRDS(file.path(CONFIG$whr_work, "proj", sprintf("proj_%d.rds", fy)))
  ic <- setNames(P$IC, P$FULL_PROJECT_NUM); act <- setNames(P$ACT, P$FULL_PROJECT_NUM)
  P <- P[!is.na(IC) & IC %in% NIH_ICS]
  if (fy %in% CONFIG$zfix_years) {        # same intramural replacement as WHR year_features()
    Z <- readRDS(file.path(CONFIG$whr_work, "proj", sprintf("projz_%d.rds", fy)))
    Z[, `:=`(IC = unname(ic[FULL_PROJECT_NUM]), ACT = unname(act[FULL_PROJECT_NUM]))]
    P <- rbind(P[!FULL_PROJECT_NUM %in% Z$FULL_PROJECT_NUM], Z, fill = TRUE)
  }
  # application id -> project number, then RCDC flag / terms rolled up to the project
  R <- readRDS(file.path(CONFIG$whr_work, "rows", sprintf("rows_%d.rds", fy)))[, .(APPLICATION_ID, FULL_PROJECT_NUM)]
  E <- readRDS(wp(sprintf("extra_%d.rds", fy)))
  E[, APPLICATION_ID := as.character(as.numeric(APPLICATION_ID))]
  R[, APPLICATION_ID := as.character(as.numeric(APPLICATION_ID))]
  E[, rcdc_api := APPLICATION_ID %in% API[FY == fy, APPLICATION_ID]]
  R <- merge(R, unique(E, by = "APPLICATION_ID"), by = "APPLICATION_ID", all.x = TRUE)
  agg <- R[!is.na(FULL_PROJECT_NUM), .(rcdc_file = any(rcdc_chd %in% TRUE), rcdc_api = any(rcdc_api %in% TRUE),
                                       terms = tolower(paste(unique(na.omit(terms)), collapse = ";"))), by = FULL_PROJECT_NUM]
  P <- merge(P, agg, by = "FULL_PROJECT_NUM", all.x = TRUE, sort = FALSE)
  P[is.na(rcdc_file), rcdc_file := FALSE]; P[is.na(rcdc_api), rcdc_api := FALSE]
  # FY2023: bulk file has no RCDC -> API; other years: bulk file (API used as a cross-check)
  P[, rcdc := if (fy == 2023) rcdc_api else rcdc_file]
  # ---- keyword features (title = lower-cased parent title; text = pooled title+abstract+PHR)
  G <- P[, .(FY = fy, FULL_PROJECT_NUM, CORE_PROJECT_NUM, IC, ACT, USD, title = PROJECT_TITLE,
             rcdc, rcdc_file, rcdc_api)]
  num0 <- c("t_str", "s_str", "s_weak", "k_str", "s_ped", "s_adu", "s_life", "s_basic", "s_hum")
  G[, (num0) := 0L]; G[, `:=`(t_ped = FALSE, t_adu = FALSE, t_pedcard = FALSE)]
  # Speed: the full CHD regex runs only on projects passing a cheap fixed-string pre-screen
  # (every strong/weak term contains one of these stems) or flagged by RCDC.
  stems <- c("congenit", "fontan", "ventric", "hypoplastic", "hlhs", "fallot", "tof ", "transposition", "tga",
             "coarctation", "aortic arch", "septal", "vsd", "atrioventricular", "ebstein", "truncus", "dorv",
             "atresia", "anomalous pulmonary", "tapv", "heterotaxy", "conotruncal", "outflow tract", "malformation",
             "birth defect", "cardiopathy", "norwood", "hybrid stage", "glenn", "cavopulmonary", "achd",
             "bicuspid", "ductus", "pda", "22q11", "digeorge", "defect", "pediatric heart", "pediatric cardiac",
             "lvoto", "noonan", "turner")
  tx <- P$text
  cand <- which(P$rcdc_file | P$rcdc_api | Reduce(`|`, lapply(stems, function(s) stri_detect_fixed(tx, s))))
  tl <- P$title_l[cand]; tx <- tx[cand]
  G[cand, `:=`(t_str = cnt(tl, CHD_STRONG), s_str = cnt(tx, CHD_STRONG), s_weak = cnt(tx, CHD_WEAK),
               k_str = cnt(lower_na(P$terms[cand]), CHD_STRONG), t_pedcard = hit(tl, PED_CARD_TITLE))]
  # age-group / basic-science features only where any CHD signal exists
  a <- cand[G$t_str[cand] + G$s_str[cand] + G$s_weak[cand] > 0 | G$rcdc[cand]]
  tl <- P$title_l[a]; tx <- P$text[a]
  G[a, `:=`(t_ped = hit(tl, PED), s_ped = cnt(tx, PED), t_adu = hit(tl, ADULT), s_adu = cnt(tx, ADULT),
            s_life = cnt(tx, LIFESPAN), s_basic = cnt(tx, BASIC), s_hum = cnt(tx, HUMAN))]
  G[]
}
G <- rbindlist(parallel::mclapply(CONFIG$years, mc.cores = 4, function(fy) { g <- build_year(fy); say(fy, ": ", nrow(g), " NIH projects, $", round(sum(g$USD) / 1e9, 2), "B"); g }))
saveRDS(G, wp("G.rds"))
