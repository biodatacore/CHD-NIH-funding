#' 02_load_shipped.R -- load the de-identified NIH IC universe shipped in
#' data/shipped/ and prepare data/work/G.rds plus candidate text for the
#' CHD-signal pool. Does not require ExPORTER bulk files or a WHR work cache.
#'
#' Usage (from the repository root):  source("R/02_load_shipped.R")
#' The loader checks MD5 checksums, reads RFC-4180 CSV via base read.csv
#' (not data.table::fread), and copies shipped CDC WONDER XML into
#' data/wonder/ when those files are not already present.

source("R/00_setup.R")

ship_root <- "data/shipped"
md5_file <- file.path(ship_root, "MD5SUMS")
if (!file.exists(md5_file)) {
  stop("Shipped extract not found at ", md5_file,
       ". This repository should include data/shipped/.")
}

# Verify checksums (paths in MD5SUMS are relative to data/shipped/).
md_lines <- readLines(md5_file, warn = FALSE)
md_lines <- md_lines[nzchar(md_lines) & !startsWith(md_lines, "#")]
bad <- character()
for (ln in md_lines) {
  h <- sub("  .*", "", ln)
  rel <- sub("^[^ ]+  ", "", ln)
  p <- file.path(ship_root, rel)
  if (!file.exists(p)) {
    bad <- c(bad, paste(rel, "MISSING"))
    next
  }
  got <- unname(tools::md5sum(p))
  if (!identical(got, h)) bad <- c(bad, paste(rel, "MD5 mismatch"))
}
if (length(bad)) stop("Shipped data checksum failed:\n  ", paste(bad, collapse = "\n  "))
say("shipped MD5 checks passed (", length(md_lines), " files)")

read_shipped_csv <- function(path) {
  # WHR convention: base read.csv, not fread, so quoting stays RFC-4180.
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  strip.white = FALSE, na.strings = c("", "NA"),
                  comment.char = "")
}

as_bool <- function(x) {
  if (is.logical(x)) { x[is.na(x)] <- FALSE; return(x) }
  y <- tolower(as.character(x))
  out <- y %in% c("true", "t", "1")
  out[is.na(x) | y %in% c("na", "")] <- FALSE
  out
}

years <- CONFIG$years
u_files <- file.path(ship_root, "universe", sprintf("chd_universe_%d.csv.gz", years))
missing_u <- u_files[!file.exists(u_files)]
if (length(missing_u)) stop("Missing universe files: ", paste(missing_u, collapse = ", "))

U <- do.call(rbind, lapply(u_files, function(f) {
  d <- read_shipped_csv(f)
  d
}))
bool_cols <- c("rcdc", "rcdc_file", "rcdc_api", "t_ped", "t_adu", "t_pedcard", "t_cardi", "cv")
for (cn in intersect(bool_cols, names(U))) U[[cn]] <- as_bool(U[[cn]])
int_cols <- c("FY", "t_str", "s_str", "s_weak", "k_str", "s_ped", "s_adu", "s_life", "s_basic", "s_hum")
for (cn in intersect(int_cols, names(U))) U[[cn]] <- as.integer(U[[cn]])
U$USD <- as.numeric(U$USD)
U$FULL_PROJECT_NUM <- as.character(U$FULL_PROJECT_NUM)
U$CORE_PROJECT_NUM <- as.character(U$CORE_PROJECT_NUM)
U$IC <- as.character(U$IC)
U$ACT <- as.character(U$ACT)
# Titles live on the candidate text extract, not on the universe (avoids
# shipping investigator names that appear in diversity-supplement titles).
if (!"title" %in% names(U)) U$title <- ""
U$title[is.na(U$title)] <- ""

# Attach scrubbed titles from the candidate text files where present.
t_files <- file.path(ship_root, "text", sprintf("chd_text_%d.csv.gz", years))
TXT <- do.call(rbind, lapply(seq_along(years), function(i) {
  f <- t_files[[i]]
  if (!file.exists(f)) return(NULL)
  d <- read_shipped_csv(f)
  d$FY <- as.integer(years[[i]])
  d
}))
if (is.null(TXT) || !nrow(TXT)) stop("No shipped candidate text files found under ", file.path(ship_root, "text"))
if (!"PROJECT_TITLE" %in% names(TXT) && "title" %in% names(TXT)) {
  TXT$PROJECT_TITLE <- TXT$title
}
TXT$FULL_PROJECT_NUM <- as.character(TXT$FULL_PROJECT_NUM)
TXT$PROJECT_TITLE <- as.character(TXT$PROJECT_TITLE)
TXT$PROJECT_TITLE[is.na(TXT$PROJECT_TITLE)] <- ""
TXT$text <- as.character(TXT$text)
TXT$text[is.na(TXT$text)] <- ""
if (!"source" %in% names(TXT)) TXT$source <- "file"
TXT$source <- as.character(TXT$source)

# Overlay candidate titles onto G so 03_classify can recompute t_cardi
# on those rows; shipped t_cardi is kept for every other row.
m <- match(paste(U$FY, U$FULL_PROJECT_NUM), paste(TXT$FY, TXT$FULL_PROJECT_NUM))
hit <- !is.na(m)
U$title[hit] <- TXT$PROJECT_TITLE[m[hit]]

data.table::setDT(U)
data.table::setDT(TXT)
saveRDS(U, wp("G.rds"))
saveRDS(TXT, wp("shipped_text.rds"))
say("loaded shipped universe: ", nrow(U), " project-years; candidate text: ", nrow(TXT))

# Place WONDER XML where R/08_wonder.R reads it (data/wonder/), from the
# shipped copies, without overwriting an already-present file.
xml_src <- file.path(ship_root, "wonder")
xml_dst <- "data/wonder"
if (dir.exists(xml_src)) {
  dir.create(xml_dst, showWarnings = FALSE, recursive = TRUE)
  for (f in list.files(xml_src, pattern = "\\.xml$", full.names = TRUE)) {
    dest <- file.path(xml_dst, basename(f))
    if (!file.exists(dest)) file.copy(f, dest)
  }
}
