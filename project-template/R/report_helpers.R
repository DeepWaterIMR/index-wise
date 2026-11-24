# report_helpers.R — software citations, sanity sentences and parameter formatting for the reports.

#' Cite the installed software used by a report
#'
#' Adds the citation() entries of the packages to the project's single bibliography
#' (references.bib) and emits narrative citations with the installed versions. Entries already
#' in the file are left as they are, so hand edits survive; only missing keys are appended.
#' @param packages Character vector of packages that influenced this report.
#' @param bibliography Path to the project's references.bib.
#' @return Invisibly, the keys that were added.
report_software <- function(packages, bibliography) {
  packages <- unique(c("base", packages))
  entries <- character()
  prose <- character()
  for (package in packages) {
    refs <- utils::citation(package)
    keys <- paste0("software-", gsub("[^A-Za-z0-9]", "", package), "-", seq_along(refs))
    for (i in seq_along(refs)) {
      ref <- refs[i]
      ref$key <- keys[i]
      entries[keys[i]] <- paste(as.character(utils::toBibtex(ref)), collapse = "\n")
    }
    label <- if (package == "base") "R" else package
    version <- if (package == "base") as.character(getRversion()) else
      as.character(utils::packageVersion(package))
    prose <- c(prose, paste0(label, " ", version, " [",
                            paste0("@", keys, collapse = "; "), "]"))
  }
  bib <- if (file.exists(bibliography)) readLines(bibliography, encoding = "UTF-8", warn = FALSE) else character()
  present <- sub("^\\s*@[A-Za-z]+\\{\\s*([^,]+),.*$", "\\1", grep("^\\s*@[A-Za-z]+\\{", bib, value = TRUE))
  missing <- setdiff(names(entries), trimws(present))
  if (length(missing)) {
    dir.create(dirname(bibliography), recursive = TRUE, showWarnings = FALSE)
    con <- file(bibliography, open = "a", encoding = "UTF-8")
    writeLines(c("", paste0(entries[missing], "\n")), con)
    close(con)
  }
  cat("The analysis and report used ", paste(prose, collapse = ", "), ".\n\n", sep = "")
  invisible(missing)
}

#' Describe sanity() results in a sentence generated from the fits
#'
#' Never hard-code "all models passed": place this inline after the sanity table.
#' @param fits Named list of sdmTMB fits.
#' @return A character string.
sanity_sentence <- function(fits) {
  check_labels <- c(
    hessian_ok = "non-positive-definite Hessian", eigen_values_ok = "small Hessian eigenvalues",
    nlminb_ok = "optimiser did not converge", range_ok = "range larger than the domain",
    gradients_ok = "large gradients", se_magnitude_ok = "large standard errors",
    se_na_ok = "missing standard errors", sigmas_ok = "near-zero variance parameters"
  )
  failed <- purrr::map(fits, function(fit) {
    s <- suppressMessages(sdmTMB::sanity(fit, silent = TRUE))
    checks <- intersect(names(check_labels), names(s))
    unname(check_labels[checks[!unlist(s[checks])]])
  })
  n_ok <- sum(lengths(failed) == 0)
  if (n_ok == length(fits)) {
    return(paste0("All ", length(fits), " models passed the sanity checks."))
  }
  bad <- failed[lengths(failed) > 0]
  paste0(n_ok, " of ", length(fits), " models passed the sanity checks. ",
         paste0(names(bad), ": ", purrr::map_chr(bad, paste, collapse = ", "),
                collapse = "; "), ".")
}

#' Format parameter estimates and CIs for tables
#'
#' Near-zero variance terms give upper CIs of Inf or ~1e172; fixed notation then prints a
#' 173-digit number that pushes a LaTeX longtable off the page.
#' @param x Numeric vector.
#' @param digits Significant digits.
#' @return Character vector; values >= 1e4 in scientific notation.
format_par_value <- function(x, digits = 3) {
  dplyr::case_when(
    is.na(x) ~ NA_character_,
    is.infinite(x) ~ ifelse(x > 0, "Inf", "-Inf"),
    abs(x) >= 1e4 ~ formatC(x, format = "e", digits = digits - 1),
    TRUE ~ trimws(formatC(signif(x, digits), format = "fg", digits = digits))
  )
}

# --- Space-time block cross-validation -------------------------------------------------------

#' Matérn range of the spatial random field per model component
#'
#' The distance (km) at which the spatial correlation falls to about 0.13,
#' sqrt(8 * nu) / kappa with nu = 1 (sdmTMB's "range"; Lindgren et al. 2011).
#' @param fit An sdmTMB fit.
#' @return A tibble with component, range_km and its 95 % confidence limits.
matern_range <- function(fit) {
  comps <- if (isTRUE(fit$family$delta)) 1:2 else 1
  purrr::map_dfr(comps, function(m) {
    rp <- sdmTMB::tidy(fit, "ran_pars", model = m)
    rp <- rp[rp$term == "range", ]
    tibble::tibble(component = if (length(comps) == 2) c("encounter", "positive")[m] else "single",
                   range_km = rp$estimate[1], lwr = rp$conf.low[1], upr = rp$conf.high[1])
  })
}

#' Block size for space-time cross-validation
#'
#' `cfg$CV_BLOCK_KM` when set; otherwise the largest Matérn range of the Step 2 fit rounded up to
#' `round_km`, so that a held-out block is about as wide as the distance over which the
#' residuals stay correlated (Roberts et al. 2017; Valavi et al. 2019).
#' @param cfg Project configuration.
#' @param fit_file Path to the Step 2 base-model fit (.rds).
#' @param round_km Rounding step (km).
cv_block_size <- function(cfg, fit_file, round_km = 50) {
  if (!is.null(cfg$CV_BLOCK_KM)) return(cfg$CV_BLOCK_KM)
  round_km * ceiling(max(matern_range(readRDS(fit_file))$range_km) / round_km)
}

#' Space-time block cross-validation folds
#'
#' The region is divided into squares of `block_km` (X/Y in km); every square-year combination
#' is a group, and the groups are assigned greedily, largest first, to the fold with the fewest
#' hauls so far, which keeps the folds even although the hauls are clustered. A fold holds out
#' an area in some years while the same area stays in the training data in other years, which
#' mimics the index predicting a cell that was not sampled in a given year.
#' @return Integer fold ids with attributes `block_km` and `k`.
make_spacetime_folds <- function(dt, block_km, k = 10, seed = 1) {
  set.seed(seed)
  group <- paste(floor(dt$X / block_km), floor(dt$Y / block_km), dt$year)
  n <- table(group)
  n <- n[sample(length(n))]
  n <- n[order(-n)]
  load <- numeric(k)
  fold_of <- integer(length(n))
  for (i in seq_along(n)) {
    f <- which.min(load)
    fold_of[i] <- f
    load[f] <- load[f] + n[[i]]
  }
  structure(unname(fold_of[match(group, names(n))]), block_km = block_km, k = k)
}

#' Fold assignment saved once, so every stage scores the same held-out hauls
load_cv_folds <- function(dt, cfg, fit_file, sel_dir) {
  f <- file.path(sel_dir, "cv-folds.rds")
  if (!file.exists(f)) {
    saveRDS(make_spacetime_folds(dt, cv_block_size(cfg, fit_file), k = cfg$CV_FOLDS %||% 10), f)
  }
  folds <- readRDS(f)
  if (length(folds) != nrow(dt)) stop("Saved folds do not match the selection data; delete ", f)
  folds
}

#' Paired cross-validation comparison
#'
#' Every candidate of a cross-validated sdmTMB_selection() is scored on the same held-out hauls,
#' so the ELPD difference is summed haul by haul and its standard error is
#' sqrt(n) * sd of the per-haul differences (Vehtari et al. 2017).
#' @param sel An sdmTMB_selection() result with `cv`.
#' @param ref Reference candidate; the best by ELPD when NULL.
cv_paired <- function(sel, ref = NULL) {
  ll <- lapply(sel$cv, function(x) if (is.null(x)) NULL else x$data$cv_loglik)
  ll <- ll[!vapply(ll, is.null, logical(1))]
  elpd <- vapply(ll, sum, numeric(1), na.rm = TRUE)
  if (is.null(ref)) ref <- names(which.max(elpd))
  purrr::imap_dfr(ll, function(x, nm) {
    d <- x - ll[[ref]]
    ok <- !is.na(d)
    tibble::tibble(model = nm, elpd = sum(x, na.rm = TRUE), delta_elpd = sum(d[ok]),
                   se_delta = if (nm == ref) 0 else sqrt(sum(ok)) * stats::sd(d[ok]),
                   n = sum(ok))
  })
}
