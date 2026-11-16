#' 13a_v2_pool.R -- rebuild the CHD-signal pool from C.rds and shipped
#' candidate text (port of R/13a_v2_pool.py).
#'
#' Pool = project-years with rcdc TRUE or t_str + s_str + s_weak > 0,
#' plus extra FY rows whose shipped text matches the v2.1+ lesion / PH
#' patterns (ductus arteriosus, SVAS, coarctation, heart block, pulmonary
#' hypertension, PPHN). Text is the same FY2020/2024 intramural-replaced
#' pooled title+abstract+PHR used by the original extract (already applied
#' in the shipped text files).
#'
#' Output: data/work/v2_pool.tsv.xz (and data/work/v2_pool.rds).

source("R/00_setup.R")

if (!file.exists(wp("C.rds"))) stop("data/work/C.rds is missing; run 03_classify first")
C <- data.table::as.data.table(readRDS(wp("C.rds")))

txt_path <- wp("shipped_text.rds")
if (!file.exists(txt_path)) {
  stop("data/work/shipped_text.rds is missing; run R/02_load_shipped.R first")
}
TXT <- data.table::as.data.table(readRDS(txt_path))

# Same pattern as 13a_v2_pool.py (applied to lower-cased text).
extra_re <- "ductus arteriosus|supravalv(?:ular|ar) aortic stenosis|\\bsvas\\b|coarctation|heart block|pulmonary (?:arterial )?hypertension|\\bpphn\\b"

sig <- C[["t_str"]] + C[["s_str"]] + C[["s_weak"]]
pool <- C[rcdc == TRUE | sig > 0]
say("CHD-signal rows (rcdc or term counts): ", nrow(pool))

for (fy in CONFIG$years) {
  Tfy <- TXT[FY == fy]
  if (!nrow(Tfy)) next
  tl <- stringi::stri_trans_tolower(Tfy$text)
  hit <- stringi::stri_detect_regex(tl, extra_re)
  hit[is.na(hit)] <- FALSE
  xt <- unique(Tfy$FULL_PROJECT_NUM[hit])
  already <- pool[FY == fy, FULL_PROJECT_NUM]
  add <- C[FY == fy & FULL_PROJECT_NUM %in% xt & !(FULL_PROJECT_NUM %in% already)]
  if (nrow(add)) {
    pool <- data.table::rbindlist(list(pool, add), use.names = TRUE)
    say("  extra ", fy, ": ", nrow(add))
  }
}

# Merge text and prefer the shipped (scrubbed) title when present.
Tjoin <- unique(TXT[, .(FY, FULL_PROJECT_NUM,
                        text_ship = text,
                        title_ship = PROJECT_TITLE)],
                by = c("FY", "FULL_PROJECT_NUM"))
pool <- merge(pool, Tjoin, by = c("FY", "FULL_PROJECT_NUM"), all.x = TRUE, sort = FALSE)
n_na <- sum(is.na(pool$text_ship) | (!nzchar(ifelse(is.na(pool$text_ship), "", pool$text_ship))))
if (n_na) warning(n_na, " pool rows have no shipped text")
pool[, text := ifelse(!is.na(text_ship), as.character(text_ship), "")]
pool[, title := fifelse(!is.na(title_ship) & nzchar(title_ship),
                        as.character(title_ship),
                        as.character(title))]
pool[, c("text_ship", "title_ship") := NULL]

# Factor age -> character, matching the shipped TSV.
if (is.factor(pool$age)) pool[, age := as.character(age)]
pool[is.na(age), age := ""]

# Column order of the shipped v2_pool.tsv.xz
ord <- c("FY", "FULL_PROJECT_NUM", "CORE_PROJECT_NUM", "IC", "ACT", "USD",
         "title", "rcdc", "rcdc_file", "rcdc_api", "t_str", "s_str", "s_weak",
         "k_str", "s_ped", "s_adu", "s_life", "s_basic", "s_hum", "t_ped",
         "t_adu", "t_pedcard", "t_cardi", "kw", "rcdc_avail", "union", "ped",
         "adu", "basic_dom", "age", "text")
missing <- setdiff(ord, names(pool))
if (length(missing)) stop("pool missing columns: ", paste(missing, collapse = ", "))
pool <- pool[, ..ord]

# Write an R-readable TSV with Python-style True/False so it matches the
# shipped export after utils::read.delim (strip.white = FALSE).
write_pool_tsv_xz <- function(d, path) {
  out <- as.data.frame(d, stringsAsFactors = FALSE)
  bools <- c("rcdc", "rcdc_file", "rcdc_api", "t_ped", "t_adu", "t_pedcard",
             "t_cardi", "kw", "rcdc_avail", "union", "ped", "adu", "basic_dom")
  for (cn in intersect(bools, names(out))) {
    v <- out[[cn]]
    if (!is.logical(v)) v <- as.logical(v)
    out[[cn]] <- ifelse(is.na(v), "", ifelse(v, "True", "False"))
  }
  # Keep whole-dollar amounts as n.0, matching the shipped TSV.
  if ("USD" %in% names(out)) {
    usd <- as.numeric(out$USD)
    out$USD <- ifelse(is.na(usd), "",
                      ifelse(abs(usd - round(usd)) < 1e-9,
                             sprintf("%.1f", usd),
                             as.character(usd)))
  }
  con <- xzfile(path, open = "wt", compression = 9)
  on.exit(close(con), add = TRUE)
  utils::write.table(out, con, sep = "\t", row.names = FALSE, col.names = TRUE,
                     quote = TRUE, na = "", qmethod = "double",
                     fileEncoding = "UTF-8")
}

out_tsv <- wp("v2_pool.tsv.xz")
write_pool_tsv_xz(pool, out_tsv)
saveRDS(pool, wp("v2_pool.rds"))
say("wrote ", out_tsv, " (", nrow(pool), " project-years)")
