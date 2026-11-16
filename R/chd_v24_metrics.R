# Shared validation metrics and stratified bootstrap (seed 1, 2,000 draws).
# When a shipped index file is present, CIs match the Python numpy Generator
# (default_rng(1)) exactly. Otherwise CIs are re-derived with R's RNG.

B_DEFAULT <- 2000L
SEED_DEFAULT <- 1L

chd_metr <- function(pp, rp, w) {
  pp <- as.logical(pp); rp <- as.logical(rp); w <- as.numeric(w)
  tp <- sum(w[pp & rp]); fp <- sum(w[pp & !rp]); fn <- sum(w[!pp & rp]); tn <- sum(w[!pp & !rp])
  n <- tp + fp + fn + tn
  po <- if (n > 0) (tp + tn) / n else NA_real_
  pe <- if (n > 0) ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / n^2 else NA_real_
  f <- function(a, b) if ((a + b) > 0) a / (a + b) else NA_real_
  kappa <- if (!is.na(pe) && pe < 1) (po - pe) / (1 - pe) else NA_real_
  list(Sensitivity = f(tp, fn), Specificity = f(tn, fp), PPV = f(tp, fp), NPV = f(tn, fn),
       Accuracy = po, Kappa = kappa, TP = tp, FP = fp, FN = fn, TN = tn)
}

chd_wilson <- function(k, n, z = 1.96) {
  if (is.na(k) || is.na(n) || n == 0) return(c(NA_real_, NA_real_))
  p <- k / n
  d <- 1 + z * z / n
  c0 <- (p + z * z / (2 * n)) / d
  h <- z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
  c(c0 - h, c0 + h)
}

# Read a 2000 x n matrix of 0-based indices (uint32 LE, header: nrow, ncol).
read_boot_idx <- function(path) {
  con <- if (grepl("\\.xz$", path)) xzfile(path, "rb") else if (grepl("\\.gz$", path)) gzfile(path, "rb") else file(path, "rb")
  on.exit(close(con), add = TRUE)
  hdr <- readBin(con, "integer", n = 2L, size = 4L, endian = "little")
  nr <- hdr[1]; nc <- hdr[2]
  m <- readBin(con, "integer", n = nr * nc, size = 4L, endian = "little")
  if (length(m) != nr * nc) stop("truncated bootstrap index file: ", path)
  matrix(m, nrow = nr, ncol = nc, byrow = TRUE)
}

write_boot_idx <- function(mat, path) {
  # mat: 0-based, nrow draws, ncol observations
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  con <- if (grepl("\\.xz$", path)) xzfile(path, "wb") else if (grepl("\\.gz$", path)) gzfile(path, "wb") else file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(as.integer(c(nrow(mat), ncol(mat))), con, size = 4L, endian = "little")
  writeBin(as.integer(as.vector(t(mat))), con, size = 4L, endian = "little")
}

chd_boot_quantiles <- function(pp, rp, w, st, B = B_DEFAULT, seed = SEED_DEFAULT, idx = NULL, idx_path = NULL) {
  pp <- as.logical(pp); rp <- as.logical(rp); w <- as.numeric(w)
  st <- as.character(st)
  n <- length(pp)
  if (!is.null(idx_path) && file.exists(idx_path) && is.null(idx)) {
    idx <- read_boot_idx(idx_path)
  }
  if (is.null(idx)) {
    # R fallback RNG (documented; CIs will not match numpy).
    # Stratified with-replacement, first-appearance stratum order (like pandas.unique).
    levels <- unique(st)
    g <- lapply(levels, function(s) which(st == s))
    set.seed(seed)
    idx <- matrix(NA_integer_, B, n)
    for (b in seq_len(B)) {
      take <- unlist(lapply(g, function(x) sample(x, length(x), replace = TRUE)), use.names = FALSE)
      idx[b, ] <- take - 1L  # store 0-based for consistency
    }
  }
  if (nrow(idx) != B || ncol(idx) != n) {
    stop("bootstrap index matrix has shape ", paste(dim(idx), collapse = "x"),
         " but expected ", B, "x", n)
  }
  keys <- c("Sensitivity", "Specificity", "PPV", "NPV", "Accuracy", "Kappa")
  out <- matrix(NA_real_, B, length(keys))
  colnames(out) <- keys
  for (b in seq_len(B)) {
    ii <- idx[b, ] + 1L
    m <- chd_metr(pp[ii], rp[ii], w[ii])
    out[b, ] <- vapply(keys, function(k) m[[k]], numeric(1))
  }
  qs <- apply(out, 2, quantile, probs = c(0.025, 0.975), names = FALSE, type = 7)
  # apply on columns yields 2 x K; match pandas default quantile (linear, type 7)
  list(lo = qs[1, ], hi = qs[2, ], idx = idx)
}

# De-identify trailing person names in titles (port of 14_v2_run.py).
chd_deidentify_title <- function(title) {
  title <- ifelse(is.na(title), "", as.character(title))
  rx <- r"---((?i)\b(supplement|fellowship|award|scholar)\s*[-:]\s*[A-Z][a-z]+(?:\s+[A-Z]\.?)?(?:\s+[A-Z][a-z'\-]+)+\s*$)---"
  gsub(rx, "\\1 - [NAME]", title, perl = TRUE)
}

# Repo-root helper.
chd_root <- function() {
  env <- Sys.getenv("CHD_ROOT", unset = "")
  if (nzchar(env) && dir.exists(env)) return(normalizePath(env))
  # if cwd is repo root
  if (file.exists("R/23_v24_classify.R")) return(normalizePath("."))
  args <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args, value = TRUE)
  if (length(f)) {
    p <- normalizePath(sub("^--file=", "", f[[1]]))
    cand <- normalizePath(file.path(dirname(p), ".."))
    if (file.exists(file.path(cand, "R/23_v24_classify.R"))) return(cand)
  }
  normalizePath(".")
}

chd_round <- function(x, nd) {
  # same half-to-even as Python / R default
  round(x, nd)
}
