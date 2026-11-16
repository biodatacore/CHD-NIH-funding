# 23_v24_classify.R -- v2.4 CHD classifier (R port of R/13_v2_rules.py).
# Applied to the CHD-signal pool (data/work/v2_pool.tsv.xz, generated from
# data/work/v2_pool.pkl.gz). Regex patterns are the Python originals; matching
# uses PCRE (perl = TRUE) to follow the Python `re` engine.
#
# Usage (from repository root):
#   source("R/23_v24_classify.R")
#   D <- chd_classify(load_v2_pool())

chd_hit <- function(s, rx) {
  s <- as.character(s)
  s[is.na(s)] <- ""
  grepl(rx, s, perl = TRUE)
}

chd_cnt <- function(s, rx) {
  s <- as.character(s)
  s[is.na(s)] <- ""
  m <- gregexpr(rx, s, perl = TRUE)
  vapply(m, function(x) {
    if (length(x) == 1L && (is.na(x[1L]) || x[1L] == -1L)) 0L else length(x)
  }, integer(1L))
}

chd_select <- function(conds, values, default) {
  n <- length(conds[[1L]])
  out <- rep(default, n)
  for (i in rev(seq_along(conds))) {
    out[conds[[i]] & !is.na(conds[[i]])] <- values[[i]]
  }
  out
}

chd_as_logical <- function(x) {
  if (is.logical(x)) {
    x[is.na(x)] <- FALSE
    return(x)
  }
  if (is.numeric(x)) return(!is.na(x) & x != 0)
  x <- tolower(trimws(as.character(x)))
  x %in% c("true", "t", "1", "yes")
}

# Auto-copied regex constants from R/13_v2_rules.py (byte-identical patterns).
FONTAN_FIX <- r"---(\bfontan(?!el|a))---"
ACQUIRED <- r"---((post-?infarction|post-?myocardial infarction|acquired (ventricular septal|vsd)))---"
DEV <- r"---(\b(neural crest|outflow tract|inflow tract|septation|endocardial cushion|cushion (formation|mesenchyme)|valv(e|ular) (development|formation|morphogenesis|delamination|progenitor)|valvulogenesis|heart valve development|heart tube|cardiac looping|heart looping|looping morphogenesis|second heart field|first heart field|heart field|cardiac progenitors?|cardiac mesoderm|cardiogenesis|cardioblasts?|cardiac (development|morphogenesis|chamber)|heart (development|morphogenesis|formation|regeneration and development)|chamber (formation|morphogenesis)|ventricular (morphogenesis|compaction)|trabeculation|aortic arch arter|pharyngeal arch arter|left-right (asymmetry|patterning|axis)|laterality|proepicardi|developing heart|embryonic heart|fetal heart development|cardiovascular development|cardiac gene regulat))---"
DEV_MODEL <- r"---(\b(zebrafish|drosophila|mouse embryo|mice|murine|chick|xenopus|embryo|ipsc|organoid))---"
DEVICE_T <- r"---(\b(stent|valve|valved conduit|conduit|graft|cannula|pump|lvad|vad|assist device|device|catheter|oximet|screening|flow restrictor|banding|tissue[- ]engineered|bioprosthe|implant|shunt|patch))---"
PED_T <- r"---(\b(pediatric|paediatric|neonat|newborn|infant|baby|babies|child|children|fetal|fetus|congenital))---"
CARD_T <- r"---((heart|cardi|valv|ventric|atri|aort|pulmonary arter|vascul|vessel|outflow|myocard))---"
PLATFORM_T <- r"---(\b(software|computing|artificial intelligence|deep learning|data science|cobre|genotyping|services|sbir topic|imaging application|global network|brain age))---"
CENTER_T <- r"---(\b(cobre|center for|centre for|center of|research center|institutional development))---"
CHD_TITLE_OK <- r"---((congenital|cchd|chds?\b|bicuspid|\bbav\b|birth defect|fontan(?!el|a)|single ventricle|hypoplastic|fallot|septal defect|heterotaxy|conotruncal|pediatric heart|pediatric cardi))---"
BASIC_RX <- r"---(\b(mice|mouse|murine|zebrafish|xenopus|chick|drosophila|embryos?|embryonic|organoids?|ipsc|induced pluripotent|stem cells?|cardiomyocytes?|cardiac (development|progenitor|neural crest)|second heart field|heart (development|morphogenesis)|transcription factor|gene regulatory|enhancers?|chromatin|signaling pathway|knockout|in vitro|in silico|computational model))---"
HUMAN_RX <- r"---(\b(patients?|surger(y|ies)|surgical|cohorts?|trials?|registry|registries|clinical|hospitali[sz]|hospitals?|survivors?|participants|enroll(ed|ment)?|quality of life|catheteri[sz]ation|transplant(ation)?|echocardiogra|first-in-(baby|human)))---"
LESION_V21 <- r"---(\b(patent ductus arteriosus|ductus arteriosus|supravalv(ular|ar) aortic stenosis|\bsvas\b))---"
COARC_V22 <- r"---((?<!aortic )\bcoarctation\b(?! of the aorta))---"
CHB_V22 <- r"---(\b((fetal|neonatal|autoimmune) (complete )?(congenital )?heart block|neonatal lupus|anti-?(ro|ssa)\b[^.]{0,80}heart block))---"
PH_RX <- r"---(\b(pulmonary (arterial )?hypertension|\bpah\b|\bpphn\b))---"
PEDPH_TXT <- r"---(\b((pediatric|paediatric|neonatal|infant|childhood|newborn|persistent) pulmonary (arterial )?hypertension|\bpphn\b|bronchopulmonary dysplasia[- ]associated pulmonary hypertension))---"
PED_TITLE_PH <- r"---(\b(pediatric|paediatric|neonat|newborn|infant|child|children|childhood|preterm|premature|fetal|bronchopulmonary dysplasia))---"
CHD_STRONG_NOBLOCK <- r"---(\b(congenital (heart|cardiac|cardiovascular) (disease|defect|malformation|anomal|lesion|surgery|surgical)|congenital heart(?! block)|achd|fontan(?!el|a)|single[- ]ventricle|univentricular|hypoplastic left heart|tetralogy|transposition of the great|septal defect|atrioventricular canal|ebstein|truncus arteriosus|double[- ]outlet|pulmonary atresia|tricuspid atresia|anomalous pulmonary venous|heterotaxy|conotruncal|norwood|glenn|cavopulmonary|eisenmenger|shunt))---"
EXCL_V23 <- r"---((heart block|neonatal lupus|non-?compaction|noncompact|pulmonary (arterial )?hypertension|\bpphn\b|\bpah\b))---"
CHB_RX <- r"---(\bcongenital (heart|cardiac) block)---"
DEV_LAT <- r"---(\b(left-right (asymmetry|patterning|axis)|laterality))---"
LAT_CARD_LINK <- r"---((\bhearts?\b|cardiac|cardiogen|ventricl|atri(?:um|al|oventricular)|\bchds?\b(?!\d)|\bachd\b|outflow tract|conotruncal|septal defect|fontan(?!el|a)|fallot|hypoplastic left|ebstein|norwood|glenn|cavopulmonary|double[- ]outlet|transposition of the great|truncus arteriosus|coarctation|patent ductus|arterial ductus|supravalv|\bsvas\b|bicuspid aortic|cardiac looping|heart looping|c-looping))---"
CHD_TITLE_V24 <- r"---((congenital|cchd|chds?\b|bicuspid|\bbav\b|birth defect|fontan(?!el|a)|single ventricle|hypoplastic|fallot|septal defect|heterotaxy|conotruncal|pediatric heart|pediatric cardi)|arterial ductus|ductus arteriosus|patent ductus|\bsvas\b|supravalv|coarctation|cardiac situs|single[- ]ventricle)---"
CHD_SENT <- r"---(\b(congenital (heart|cardiac|cardiovascular) (disease|defect|malformation|anomal|lesion|surgery|surgical)|congenital heart(?! block)|achd|fontan(?!el|a)|single[- ]ventricle|univentricular|hypoplastic left heart|tetralogy|transposition of the great|septal defect|atrioventricular canal|ebstein|truncus arteriosus|double[- ]outlet|pulmonary atresia|tricuspid atresia|anomalous pulmonary venous|heterotaxy|conotruncal|norwood|glenn|cavopulmonary|eisenmenger|shunt)|\b(patent ductus arteriosus|ductus arteriosus|supravalv(ular|ar) aortic stenosis|\bsvas\b)|\bcoarctation\b|arterial ductus|\bsvas\b|supravalv(ular|ar) aortic|\bachd\b|tetralogy of fallot|\bhlhs\b|hypoplastic left|transposition of the great|(atrial|ventricular|atrioventricular) septal defects?|\bavsd\b|ebstein|double[- ]outlet|\bdorv\b|fontan(?!el|a)|single[- ]ventricle|congenital (heart|cardiac)|(cardiac|heart|cardiovascular) (malformation|birth defect))---"
AIM_RX <- r"---((specific aims?|\baim\s*[1-6]\b|we (propose|aim|will|seek|hypothesize|intend|plan) to|the (overall )?(goal|objective|purpose|aims?) (of this|of the|are|is)\b|this (application|proposal|project|study|grant|work|research) (will|aims?|seeks?|proposes?|is designed)|our (goals?|objectives?|aims?|hypothesis)\b|we hypothesize|under the (first|second|third|final|current) aim))---"
ASSOC_TAIL <- r"---(,?\s*which (are|is|were|was) (the sites? of )?mutations that cause[^.]*|,?\s*which (are|is) associated with[^.]*|lead[s]? to development of[^.]*|sites? of mutations that cause[^.]*|mutations? in \S+ lead[s]? to development of[^.]*)---"
HUMAN_AGE <- list(
  ped = r"---(\b(pediatric|paediatric|child|children|childhood|infan(t|ts|cy)|neonat(e|es|al)|newborns?|fetal|fetus(es)?|prenatal|perinatal|in utero|nicu|adolescen(t|ts|ce)|youth|preterm|toddlers?|school[- ]age|cicu|norwood|interstage))---",
  adu = r"---(\b(achd|adult congenital|adults with|adult (patients|survivors|population|cohort|clinic|chd|care|outcomes|women|men)|young adults|older adults|adulthood|grown[- ]up congenital|guch|women with (congenital|chd|repaired)|aging with))---",
  life = r"---(\b(children and adults|adults and children|pediatric and adult|adult and pediatric|lifespan|life course|from (childhood|infancy|birth) (to|through|into) adulthood|transition(ing)? (from pediatric|to adult)))---"
)
TRAINEE <- c("F30", "F31")
CENTER_ACT <- c("G20", "N01", "N02", "N43", "N44", "P20", "P30", "P60", "R50", "S10", "U54")
VERSION <- "2.4"


# Load the CHD-signal pool from the shipped R-readable table (preferred).
# The csv.xz was generated from data/work/v2_pool.pkl.gz and verified
# row-for-row (see tests/r_vs_python_report.md).
# Load the CHD-signal pool from the shipped R-readable table (preferred).
# data/work/v2_pool.tsv.xz was generated from data/work/v2_pool.pkl.gz and
# verified row-for-row (see tests/r_vs_python_report.md).
# A tab-separated, quoted file is used so titles and abstracts keep leading or
# trailing spaces, embedded quotes, and newlines. utils::read.delim (not
# data.table::fread) is required so CSV-style doubled quotes un-escape correctly.
load_v2_pool <- function(path = NULL) {
  if (is.null(path) || !nzchar(path)) {
    path <- Sys.getenv("CHD_POOL", unset = "")
  }
  cands <- c(path,
             "data/work/v2_pool.tsv.xz",
             "data/work/v2_pool.csv.gz",
             "data/r/v2_pool.rds")
  cands <- unique(cands[nzchar(cands)])
  hit <- cands[file.exists(cands)]
  if (!length(hit)) {
    stop("CHD pool not found. Expected data/work/v2_pool.tsv.xz ",
         "(R-readable export of data/work/v2_pool.pkl.gz).")
  }
  path <- hit[[1L]]
  if (grepl("\\.rds$", path, ignore.case = TRUE)) {
    D <- readRDS(path)
  } else {
    sep <- if (grepl("\\.tsv(\\.xz|\\.gz)?$", path, ignore.case = TRUE)) "\t" else ","
    con <- if (grepl("\\.xz$", path, ignore.case = TRUE)) {
      xzfile(path, open = "rt")
    } else if (grepl("\\.gz$", path, ignore.case = TRUE)) {
      gzfile(path, open = "rt")
    } else {
      file(path, open = "rt")
    }
    on.exit(close(con), add = TRUE)
    D <- utils::read.delim(con, sep = sep, stringsAsFactors = FALSE,
                           check.names = FALSE, quote = "\"",
                           strip.white = FALSE, na.strings = "",
                           comment.char = "", allowEscapes = FALSE)
  }
  bools <- c("rcdc", "rcdc_file", "rcdc_api", "t_ped", "t_adu", "t_pedcard",
             "t_cardi", "kw", "rcdc_avail", "union", "ped", "adu", "basic_dom")
  for (cn in intersect(bools, names(D))) D[[cn]] <- chd_as_logical(D[[cn]])
  for (cn in intersect(c("t_str", "s_str", "s_weak", "k_str", "s_ped", "s_adu",
                         "s_life", "s_basic", "s_hum", "FY"), names(D))) {
    D[[cn]] <- as.integer(D[[cn]])
  }
  D$USD <- as.numeric(D$USD)
  D$title <- as.character(D$title); D$title[is.na(D$title)] <- ""
  D$text <- as.character(D$text); D$text[is.na(D$text)] <- ""
  D$ACT <- as.character(D$ACT)
  D
}

chd_split_sents <- function(t) {
  t <- gsub("(*UCP)\\s+", " ", t, perl = TRUE)
  parts <- strsplit(t, r"---((?<=[\.\!\?:;])\s+|\s+(?=\baim\s*[1-6]\b)|(?<=\d\))\s+)---", perl = TRUE)[[1L]]
  parts <- trimws(parts)
  parts[nzchar(parts)]
}

chd_strip_assoc_tails <- function(s) {
  gsub(ASSOC_TAIL, " ", s, perl = TRUE)
}

chd_aim_gate_flags <- function(text) {
  t <- if (is.null(text) || length(text) == 0L || is.na(text)) "" else as.character(text[[1L]])
  strong <- CHD_SENT
  if (grepl(r"---(congenital heart|heart defect|cardiac defect|\bachd\b)---", t, perl = TRUE)) {
    strong <- paste0(strong, r"---(|\bchds?\b(?!\d))---")
  }
  n_aim <- 0L; n_subst <- 0L; n_assoc <- 0L; n_strong <- 0L
  for (s in chd_split_sents(t)) {
    if (!grepl(strong, s, perl = TRUE)) next
    n_strong <- n_strong + 1L
    core <- chd_strip_assoc_tails(s)
    if (grepl(strong, core, perl = TRUE)) {
      n_subst <- n_subst + 1L
      if (grepl(AIM_RX, core, perl = TRUE)) n_aim <- n_aim + 1L
    } else {
      n_assoc <- n_assoc + 1L
    }
  }
  c(n_aim = n_aim, n_subst = n_subst, n_assoc = n_assoc, n_strong = n_strong)
}

chd_classify <- function(D, version = VERSION) {
  D <- as.data.frame(D, stringsAsFactors = FALSE)
  tl <- tolower(ifelse(is.na(D$title), "", as.character(D$title)))
  tx <- tolower(ifelse(is.na(D$text), "", as.character(D$text)))
  D$t_ped <- chd_as_logical(D$t_ped)
  D$t_pedcard <- chd_as_logical(D$t_pedcard)
  D$rcdc <- chd_as_logical(D$rcdc)
  D$kw <- chd_as_logical(D$kw)
  D$t_str <- as.integer(D$t_str)
  D$s_str <- as.integer(D$s_str)
  D$s_weak <- as.integer(D$s_weak)
  D$s_ped <- as.integer(D$s_ped)
  if (version != "2.0") {
    xt <- chd_cnt(tl, LESION_V21)
    xs <- chd_cnt(tx, LESION_V21)
    D$s_weak <- pmax(D$s_weak - chd_cnt(tx, r"---(\bpatent ductus arteriosus)---"), 0L)
    D$t_str <- D$t_str + xt
    D$s_str <- D$s_str + xs
    D$kw_v1 <- D$kw
    if (!(version %in% c("2.0", "2.1"))) {
      if (identical(version, "2.2")) {
        D$t_str <- D$t_str + chd_cnt(tl, COARC_V22) + chd_cnt(tl, CHB_V22)
        D$s_str <- D$s_str + chd_cnt(tx, COARC_V22) + chd_cnt(tx, CHB_V22)
      } else {
        D$t_str <- pmax(D$t_str + chd_cnt(tl, COARC_V22) - chd_cnt(tl, CHB_RX), 0L)
        D$s_str <- pmax(D$s_str + chd_cnt(tx, COARC_V22) - chd_cnt(tx, CHB_RX), 0L)
      }
    }
    D$kw <- (D$t_str >= 1L) | (D$s_str >= 3L) | ((D$s_str >= 2L) & (D$s_weak >= 2L)) |
      ((D$s_str >= 1L) & (D$t_pedcard | (D$t_ped & chd_hit(tl, r"---((heart|cardi))---"))))
  }
  tl_tx <- paste(tl, tx, sep = " ")
  fontana_only <- chd_hit(tl_tx, r"---(\bfontana\b)---") & !chd_hit(tl_tx, FONTAN_FIX)
  acquired <- chd_hit(tl, ACQUIRED)
  platform <- (!chd_hit(tl, CHD_TITLE_OK)) & !chd_hit(tl, DEV) & !chd_hit(tl, PED_T) &
    (chd_hit(tl, PLATFORM_T) | ((D$ACT %in% CENTER_ACT) & (chd_hit(tl, CENTER_T) | startsWith(D$ACT, "N"))))
  D$t1_drop <- chd_select(
    list(fontana_only, acquired, platform & (D$t_str == 0L)),
    c("fontana", "acquired", "platform/center"),
    ""
  )
  D$tier1 <- D$kw & (D$t1_drop == "")
  D$pedph <- rep(FALSE, nrow(D))
  if (identical(version, "2.2")) {
    adult_t <- chd_hit(tl, r"---(\b(adult|adults|older|elderly|veteran|copd|scleroderma|systemic sclerosis|left heart disease|hfpef))---")
    pedph <- (chd_hit(tl, PH_RX) & chd_hit(tl, PED_TITLE_PH)) | (chd_cnt(tx, PEDPH_TXT) >= 3L)
    D$pedph <- pedph & !adult_t & !acquired & !fontana_only
    D$tier1 <- D$tier1 | D$pedph
  }
  chd_mention <- ((D$s_str + D$s_weak + D$t_str) > 0L) |
    chd_hit(tx, r"---(congenital heart|heart defect|cardiac defect|birth defect)---")
  anchor <- D$rcdc | chd_mention
  DEV_CORE <- gsub("|left-right (asymmetry|patterning|axis)|laterality", "", DEV, fixed = TRUE)
  if (version %in% c("2.0", "2.1", "2.2", "2.3")) {
    ndev <- chd_cnt(tl, DEV) * 2L + chd_cnt(tx, DEV)
    devsci <- anchor & (ndev >= 3L) & chd_hit(tl, paste0(CARD_T, "|", DEV))
  } else {
    lat_card <- chd_hit(tl, DEV_LAT) | chd_hit(tx, DEV_LAT)
    lat_card <- lat_card & (chd_hit(tl, LAT_CARD_LINK) | chd_hit(tx, LAT_CARD_LINK))
    ndev <- chd_cnt(tl, DEV_CORE) * 2L + chd_cnt(tx, DEV_CORE)
    ndev <- ndev + (chd_cnt(tl, DEV_LAT) * 2L + chd_cnt(tx, DEV_LAT)) * as.integer(lat_card)
    title_dev <- chd_hit(tl, paste0(CARD_T, "|", DEV_CORE)) | (lat_card & chd_hit(tl, DEV_LAT))
    devsci <- anchor & (ndev >= 3L) & title_dev
    D$lat_card <- lat_card
  }
  device <- anchor & chd_hit(tl, DEVICE_T) & (chd_hit(tl, PED_T) | (D$s_ped >= 2L)) &
    (chd_hit(tl, CARD_T) | chd_hit(tl, r"---(oximet)---"))
  if (identical(version, "2.0")) {
    trainee <- (D$ACT %in% TRAINEE) & anchor & chd_hit(tl, CARD_T) &
      ((D$s_str >= 1L) | D$rcdc | (ndev >= 1L))
  } else {
    trainee <- (D$ACT %in% TRAINEE) & chd_hit(tl, CARD_T) & ((D$s_str >= 1L) | (ndev >= 1L))
  }
  excl <- platform | acquired | fontana_only |
    chd_hit(tl, r"---(\b(coronary|atherosclero|myocardial infarction|heart failure with preserved|arrhythm|channel|sudden cardiac death))---")
  D$t2_route <- chd_select(
    list(devsci, device, trainee),
    c("developmental science", "pediatric device", "trainee F30/F31"),
    ""
  )
  D$tier2 <- (!D$tier1) & (D$t2_route != "") & (!excl)
  if (!(version %in% c("2.0", "2.1", "2.2"))) {
    D$excl_v23 <- chd_hit(tl, EXCL_V23) & !chd_hit(tl, CHD_STRONG_NOBLOCK) &
      !chd_hit(tl, COARC_V22) & !chd_hit(tl, LESION_V21)
    D$tier1 <- D$tier1 & !D$excl_v23
    D$tier2 <- D$tier2 & !D$excl_v23
  }
  if (!(version %in% c("2.0", "2.1", "2.2", "2.3"))) {
    chd_title <- (D$t_str >= 1L) | chd_hit(tl, CHD_TITLE_V24) | (chd_hit(tl, PED_T) & chd_hit(tl, CARD_T))
    kept_lesion <- chd_hit(tl, LESION_V21) | chd_hit(tx, LESION_V21) |
      chd_hit(tl, COARC_V22) | chd_hit(tx, COARC_V22) |
      chd_hit(tl, r"---(arterial ductus|\bsvas\b)---") | chd_hit(tx, r"---(arterial ductus|\bsvas\b)---")
    dev_rich <- ((chd_cnt(tl, DEV_CORE) * 2L + chd_cnt(tx, DEV_CORE)) >= 3L) &
      (chd_hit(tl, CHD_SENT) | chd_hit(tx, CHD_SENT))
    flags <- lapply(tx, chd_aim_gate_flags)
    D$t1_n_aim <- vapply(flags, `[[`, integer(1L), 1L)
    D$t1_n_subst <- vapply(flags, `[[`, integer(1L), 2L)
    D$t1_n_assoc <- vapply(flags, `[[`, integer(1L), 3L)
    demote <- D$tier1 & !chd_title & !kept_lesion & !dev_rich &
      (D$t1_n_aim == 0L) & (D$t1_n_subst < 2L) & (D$t1_n_assoc >= 1L)
    D$t1_drop[demote & (D$t1_drop == "")] <- "phenotype-only mention"
    D$tier1[demote] <- FALSE
    D$tier2 <- (!D$tier1) & (D$t2_route != "") & (!excl)
    if ("excl_v23" %in% names(D)) {
      D$tier2 <- D$tier2 & !D$excl_v23
    }
  }
  D$chd_v2 <- D$tier1 | D$tier2
  D$tier <- chd_select(
    list(D$tier1, D$tier2),
    c("Tier 1 CHD-focused", "Tier 2 CHD-related basic/developmental"),
    "Not CHD"
  )
  ped <- chd_hit(tl, HUMAN_AGE$ped) | (chd_cnt(tx, HUMAN_AGE$ped) >= 2L)
  adu <- chd_hit(tl, HUMAN_AGE$adu) | (chd_cnt(tx, HUMAN_AGE$adu) >= 2L)
  life <- chd_cnt(tx, HUMAN_AGE$life) >= 1L
  nb <- chd_cnt(tx, BASIC_RX)
  nh <- chd_cnt(tx, HUMAN_RX)
  tage <- chd_hit(tl, HUMAN_AGE$ped) | chd_hit(tl, HUMAN_AGE$adu)
  basic <- ((!tage) & (nb >= 3L) & (nb > nh)) | ((D$t2_route == "developmental science") & (!tage))
  D$age_v2 <- chd_select(
    list(basic, (ped & adu) | (life & (ped | adu)), ped, adu),
    c("Not age-specific", "Both", "Pediatric", "Adult"),
    "Not age-specific"
  )
  D
}
