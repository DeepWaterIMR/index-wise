# report_helpers.R — software citations, sanity sentences and parameter formatting for the reports.

#' Cite the installed software used by a report
#'
#' Adds the citation() entries of the packages to the project's single bibliography
#' (references.bib) and emits narrative citations with the installed versions. Entries already
#' in the file are left as they are, so hand edits survive; only missing keys are appended. A
#' citation whose DOI is already in the file (a published paper) is cited by that entry instead.
#' @param packages Character vector of packages that influenced this report.
#' @param bibliography Path to the project's references.bib.
#' @return Invisibly, the keys that were added.
report_software <- function(packages, bibliography) {
  packages <- unique(c("base", packages))
  bib <- if (file.exists(bibliography)) readLines(bibliography, encoding = "UTF-8", warn = FALSE) else character()
  # Keys already in the file, and the key of each DOI, so that a package whose citation is a
  # paper already in the library (e.g. a journal article) is cited by that entry.
  is_head <- grepl("^\\s*@[A-Za-z]+\\{", bib)
  head_key <- trimws(sub("^\\s*@[A-Za-z]+\\{\\s*([^,]+),.*$", "\\1", bib))
  entry_key <- head_key[is_head][cumsum(is_head)[cumsum(is_head) > 0]]
  entry_lines <- bib[cumsum(is_head) > 0]
  doi_rows <- grepl("^\\s*doi\\s*=", entry_lines, ignore.case = TRUE)
  doi_key <- stats::setNames(entry_key[doi_rows],
    tolower(gsub("^\\s*doi\\s*=\\s*[{\"]|[}\"],?\\s*$", "", entry_lines[doi_rows], ignore.case = TRUE)))
  present <- head_key[is_head]
  entries <- character()
  prose <- character()
  for (package in packages) {
    refs <- utils::citation(package)
    keys <- paste0("software-", gsub("[^A-Za-z0-9]", "", package), "-", seq_along(refs))
    for (i in seq_along(refs)) {
      ref <- refs[i]
      doi <- tolower(ref$doi %||% "")
      if (nzchar(doi) && doi %in% names(doi_key)) {
        keys[i] <- doi_key[[doi]]
        next
      }
      ref$key <- keys[i]
      entries[keys[i]] <- paste(as.character(utils::toBibtex(ref)), collapse = "\n")
    }
    label <- if (package == "base") "R" else package
    version <- if (package == "base") as.character(getRversion()) else
      as.character(utils::packageVersion(package))
    prose <- c(prose, paste0(label, " ", version, " [",
                            paste0("@", keys, collapse = "; "), "]"))
  }
  missing <- setdiff(names(entries), present)
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

# Model data exactly as the fit documents build them: stations inside the stock prediction
# region (read_prediction_region(), restrict_to_region()), with depth, plus the year and month
# factors and the fishable-biomass response when the data have one. Used by the validation
# scripts and documents so that every step fits the same records.
load_model_data <- function(cfg, out_dir, crs) {
  dt_all <- readRDS(file.path(out_dir, "compiled-data.rds"))
  dt <- prepare_model_data(dt_all, cfg)
  # A broader acquisition polygon with a region field: keep the model domain (REGION).
  if (isTRUE(cfg$ADD_REGION_IDENTIFIER) && "region" %in% names(dt) && !is.null(cfg$REGION))
    dt <- dt[dt$region %in% cfg$REGION, ]
  dt <- restrict_to_region(dt, read_prediction_region(cfg, crs))
  dt <- dplyr::filter(dt, !is.na(depth))
  dt$fyear <- factor(dt$year)
  if ("fmonth" %in% names(dt)) dt$fmonth <- droplevels(dt$fmonth)
  # The fishable (over OVER_CM) response on the scale of `value`: density, or catch with an
  # offset. NA when the compiled data have no fishable part.
  fish_col <- if (identical(effort_mode(cfg), "offset")) "biomass_fishable" else "rho_biomass_fishable"
  dt$value_fishable <- if (fish_col %in% names(dt)) dt[[fish_col]] else NA_real_
  dt
}

# Matérn range of the spatial random field per model component, in km: the distance at which
# the correlation falls to about 0.13, sqrt(8 * nu) / kappa with nu = 1 (sdmTMB's "range").
matern_range <- function(fit) {
  comps <- if (isTRUE(fit$family$delta)) 1:2 else 1
  purrr::map_dfr(comps, function(m) {
    rp <- sdmTMB::tidy(fit, "ran_pars", model = m)
    rp <- rp[rp$term == "range", ]
    tibble::tibble(component = if (length(comps) == 2) c("encounter", "positive")[m] else "single",
                   range_km = rp$estimate[1], lwr = rp$conf.low[1], upr = rp$conf.high[1])
  })
}

# Block size for space-time cross-validation: cfg$CV_BLOCK_KM when set, otherwise the largest
# Matérn range of the base (total biomass IID) model rounded up to `round_km`, so that a
# held-out block is about as wide as the distance over which residuals stay correlated
# (Roberts et al. 2017; Valavi et al. 2019).
cv_block_size <- function(cfg, out_dir, round_km = 50) {
  if (!is.null(cfg$CV_BLOCK_KM)) return(cfg$CV_BLOCK_KM)
  fit <- readRDS(file.path(out_dir, "model-fit-total-iid.rds"))
  round_km * ceiling(max(matern_range(fit)$range_km) / round_km)
}

# Space-time block cross-validation folds. `X`/`Y` are in km. The region is divided into
# squares of `block_km`; every square-year combination is a group, and the groups are assigned
# greedily, largest first, to the fold with the fewest hauls so far, which keeps the folds even
# although the hauls are clustered. A fold holds out an area in some years while the same area
# stays in the training data in the other years, which mimics the index predicting a cell that
# was not sampled in a given year.
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

# Fold assignment saved once per species, so every stage scores the same held-out hauls.
# The hauls are stored with the folds, so folds made for other model data are never reused.
load_cv_folds <- function(dt, cfg, out_dir, sel_dir) {
  f <- file.path(sel_dir, "cv-folds.rds")
  if (!file.exists(f)) {
    folds <- make_spacetime_folds(dt, cv_block_size(cfg, out_dir), k = cfg$CV_FOLDS %||% 10)
    attr(folds, "haul_id") <- dt$haul_id
    saveRDS(folds, f)
  }
  folds <- readRDS(f)
  if (length(folds) != nrow(dt) ||
      (!is.null(attr(folds, "haul_id")) && !identical(attr(folds, "haul_id"), dt$haul_id))) {
    stop("Saved folds do not match the model data; delete ", f)
  }
  folds
}

# Four-panel mesh-selection figure: (a) paired CV ELPD difference, when cross-validated; (b) index
# difference from the finest mesh; (c) fit time with vertex counts; (d) the index per cutoff.
plot_mesh_selection <- function(stability, index, selected, tol, window) {
  x_scale <- ggplot2::scale_x_reverse(
    breaks = stability$cutoff_km, expand = ggplot2::expansion(mult = 0.08)
  )
  fill_sel <- ggplot2::scale_fill_manual(values = c(`TRUE` = "black", `FALSE` = "white"), guide = "none")
  stability$selected <- stability$model == selected

  p_elpd <- ggplot2::ggplot(stability, ggplot2::aes(.data$cutoff_km, .data$delta_elpd)) +
    ggplot2::geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$delta_elpd - .data$se_delta, ymax = .data$delta_elpd + .data$se_delta),
      width = 2
    ) +
    ggplot2::geom_point(ggplot2::aes(fill = .data$selected), shape = 21, size = 2.3) +
    x_scale + fill_sel +
    ggplot2::labs(x = NULL, y = "ΔELPD")

  rho_long <- stability |>
    dplyr::select("cutoff_km", "selected", `Δρ (last years)` = "mesh_rho", Terminal = "terminal") |>
    tidyr::pivot_longer(c("Δρ (last years)", "Terminal"), names_to = "summary", values_to = "rel_diff")
  p_rho <- ggplot2::ggplot(rho_long, ggplot2::aes(.data$cutoff_km, 100 * .data$rel_diff)) +
    ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = -100 * tol, ymax = 100 * tol, alpha = 0.15) +
    ggplot2::geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
    ggplot2::geom_line(ggplot2::aes(linetype = .data$summary), colour = "grey40") +
    ggplot2::geom_point(ggplot2::aes(shape = .data$summary, fill = .data$selected), size = 2.3) +
    ggplot2::scale_shape_manual(values = c(21, 24)) +
    x_scale + fill_sel +
    ggplot2::labs(x = NULL, y = "Difference (%)", shape = NULL, linetype = NULL) +
    ggplot2::theme(legend.position = c(0.98, 0.98), legend.justification = c(1, 1),
                   legend.background = ggplot2::element_blank(), legend.key.height = grid::unit(0.8, "lines"))

  p_time <- ggplot2::ggplot(stability, ggplot2::aes(.data$cutoff_km, .data$fit_minutes)) +
    ggplot2::geom_line(colour = "grey60") +
    ggplot2::geom_point(ggplot2::aes(fill = .data$selected), shape = 21, size = 2.3) +
    ggplot2::geom_text(ggplot2::aes(label = .data$vertices), vjust = -0.9, size = 2.8) +
    x_scale + fill_sel +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.05, 0.3))) +
    ggplot2::labs(x = "Mesh cutoff (km)", y = "Fit time (min)")

  lev <- stability$model[order(-stability$cutoff_km)]
  idx <- index |> dplyr::mutate(mesh = factor(.data$model, levels = lev))
  p_index <- ggplot2::ggplot(idx, ggplot2::aes(.data$year, .data$est, colour = .data$mesh, fill = .data$mesh)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lwr, ymax = .data$upr), alpha = 0.08, colour = NA) +
    ggplot2::geom_line(ggplot2::aes(linewidth = .data$model == selected)) +
    ggplot2::scale_linewidth_manual(values = c(`TRUE` = 1.1, `FALSE` = 0.45), guide = "none") +
    ggplot2::scale_colour_viridis_d(end = 0.9) +
    ggplot2::scale_fill_viridis_d(end = 0.9) +
    ggplot2::labs(x = "Year", y = "Index", colour = "Mesh cutoff", fill = "Mesh cutoff") +
    ggplot2::theme(legend.position = "bottom") +
    ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2), fill = ggplot2::guide_legend(nrow = 2))

  # Without cross-validation there is no ELPD panel; the selection does not need it.
  left <- if (all(is.na(stability$delta_elpd))) list(p_rho, p_time) else list(p_elpd, p_rho, p_time)
  cowplot::plot_grid(
    cowplot::plot_grid(plotlist = left, ncol = 1, align = "v", labels = letters[seq_along(left)]),
    p_index,
    ncol = 2, rel_widths = c(1, 1.25), labels = c("", letters[length(left) + 1])
  )
}

# Paired cross-validation comparison from a sdmTMB_selection() run with cv. Every candidate is
# scored on the same held-out hauls, so the difference is summed haul by haul. Its standard
# error is computed from the sums over the space-time block groups (`group`, see cv_groups()):
# hauls of one square-year group are held out together and their differences are correlated,
# so the haul-level SE sqrt(n) * sd(d) (Vehtari et al. 2017) would be too small. Without
# `group` the haul-level SE is used. The groups are kept as an attribute for later pairs.
cv_paired <- function(sel, ref = NULL, group = NULL) {
  ll <- lapply(sel$cv, function(x) if (is.null(x)) NULL else x$data$cv_loglik)
  ll <- ll[!vapply(ll, is.null, logical(1))]
  elpd <- vapply(ll, sum, numeric(1), na.rm = TRUE)
  if (is.null(ref)) ref <- names(which.max(elpd))
  purrr::imap_dfr(ll, function(x, nm) {
    d <- x - ll[[ref]]
    ok <- !is.na(d)
    tibble::tibble(model = nm, elpd = sum(x, na.rm = TRUE), delta_elpd = sum(d[ok]),
                   se_delta = if (nm == ref) 0 else paired_se(d, group),
                   n = sum(ok))
  }) |>
    dplyr::mutate(z = ifelse(.data$se_delta > 0, .data$delta_elpd / .data$se_delta, NA_real_)) |>
    structure(pointwise = ll, group = group)
}

#' Standard error of a summed paired difference
#'
#' @param d Per-haul differences of the log predictive density (NA allowed).
#' @param group Optional grouping of the hauls (space-time block groups). With groups, the SE
#'   is `sqrt(G) * sd(D_g)` of the G group sums `D_g`, which allows for correlation within a
#'   group; without, `sqrt(n) * sd(d)`.
#' @return The standard error of `sum(d)`.
paired_se <- function(d, group = NULL) {
  ok <- !is.na(d)
  if (is.null(group)) return(sqrt(sum(ok)) * stats::sd(d[ok]))
  g <- tapply(d[ok], group[ok], sum)
  sqrt(length(g)) * stats::sd(g)
}

#' Space-time block group of each haul, as used for the CV folds
#'
#' @param dt Model data with X, Y (km) and year.
#' @param block_km Block size (km), `attr(folds, "block_km")`.
#' @return Character vector of square-year groups.
cv_groups <- function(dt, block_km) paste(floor(dt$X / block_km), floor(dt$Y / block_km), dt$year)

# Per-fold convergence and log-likelihood of each candidate in a cross-validated selection.
cv_folds_table <- function(sel) {
  purrr::imap_dfr(sel$cv, function(x, nm) {
    if (is.null(x)) return(tibble::tibble(model = nm, fold = NA_integer_))
    tibble::tibble(model = nm, fold = seq_along(x$fold_loglik), fold_loglik = x$fold_loglik,
                   pdHess = as.logical(x$pdHess),
                   converged = as.logical(x$converged %||% rep(NA, length(x$fold_loglik))))
  })
}

# Each selection stage starts from the incoming model (the model selected at the previous stage)
# and ends with the selected model, which becomes the incoming model of the next stage.
stage_incoming <- function(res) res$incoming %||% names(res$specs)[1]

# Paired cross-validation difference between candidates `a` and `b` of a stage (a - b), with
# the standard error of the haul-by-haul difference.
stage_pair <- function(res, a, b) {
  pw <- attr(res$cv, "pointwise")
  if (is.null(pw[[a]]) || is.null(pw[[b]])) return(c(d = NA_real_, se = NA_real_))
  dd <- pw[[a]] - pw[[b]]
  ok <- !is.na(dd)
  c(d = sum(dd[ok]), se = if (a == b) 0 else paired_se(dd, attr(res$cv, "group")))
}

fmt_pair <- function(x) paste0(sprintf("%+.1f", x[["d"]]), " ± ", sprintf("%.1f", x[["se"]]))

# Mean absolute relative difference (MARD) between two indices, each divided by its own series
# mean first, so that a difference in level (e.g. between families) does not count, only in trend.
index_mard <- function(a, b) {
  if (is.null(a) || is.null(b)) return(NA_real_)
  yr <- intersect(a$year, b$year)
  x <- a$est[match(yr, a$year)]; y <- b$est[match(yr, b$year)]
  mean(abs((x / mean(x)) / (y / mean(y)) - 1))
}

# Candidates eligible under the one-standard-error rule: ELPD within one paired SE of the best
# cross-validated candidate (of `models`, default all cross-validated ones).
stage_eligible <- function(res, models = res$cv$model) {
  pw <- attr(res$cv, "pointwise")
  models <- models[models %in% names(pw)]
  if (!length(models)) return(character())
  elpd <- vapply(pw[models], sum, numeric(1), na.rm = TRUE)
  top <- models[which.max(elpd)]
  models[vapply(models, function(m) {
    p <- stage_pair(res, m, top); m == top || p[["d"]] >= -p[["se"]]
  }, logical(1))]
}

# Selection sets of a stage: each set has its own best candidate and its own one-SE band. The
# random-field stage selects the assessment structure among the IID + year candidates and the
# smoothed-index structure among the smoothed candidates without a year factor. The Smoothed set
# also holds AR1 + year (AR1 or random-walk fields with a year factor), compared with the
# smoothed candidates but not selectable, because the smoothed index has no year factor; other
# structures are compared with the best IID + year candidate and reported only.
stage_set <- function(res, m) {
  if (!identical(res$stage, "fields")) return("All")
  sp <- res$specs[[m]]
  if (is_iid_year_spec(sp)) "IID + year" else if (is_smoothed_set_spec(sp)) "Smoothed" else "Other"
}

# Candidates of the selection set `set` from which the rule selects: for Smoothed, those without
# a year factor; for Other, none.
stage_selectable <- function(res, models, set) {
  models <- models[vapply(models, function(m) m %in% names(res$specs) && stage_set(res, m) == set, logical(1))]
  if (set == "Smoothed") models <- models[vapply(models, function(m) is_smoothed_spec(res$specs[[m]]), logical(1))]
  if (set == "Other") character() else models
}

stage_best <- function(res, models) {
  pw <- attr(res$cv, "pointwise")
  models <- models[models %in% names(pw)]
  if (!length(models)) return(NA_character_)
  models[which.max(vapply(pw[models], sum, numeric(1), na.rm = TRUE))]
}

# Smoothed-index structure of the random-field stage: recorded by the stage, or for a stage run
# before it was recorded, the smoothed candidate with the fewest parameters within one SE of
# the best cross-validated smoothed candidate.
stage_smoothed <- function(res) {
  if (!identical(res$stage, "fields")) return(NA_character_)
  if (!is.null(res$smoothed)) return(res$smoothed)
  close <- stage_eligible(res, stage_selectable(res, res$cv$model, "Smoothed"))
  if (!length(close)) return(NA_character_)
  close[which.min(vapply(close, function(m) smooth_size_spec(res$specs[[m]]), numeric(1)))]
}

# Table of one selection stage written by R/validation/stage_lib.R: AIC for every candidate;
# for the cross-validated candidates, the paired ELPD difference from the best candidate of the
# same selection set and its SE, so that a candidate is within one SE of the best when
# ΔELPD >= -SE(Δ); and the MARD of its index from the incoming model's index.
stage_table <- function(res) {
  inc <- stage_incoming(res)
  sel <- res$carried
  smo <- stage_smoothed(res)
  fields <- identical(res$stage, "fields")
  set_of <- function(m) if (m %in% names(res$specs)) stage_set(res, m) else NA_character_
  cvt <- tibble::tibble(model = res$cv$model) |>
    dplyr::mutate(set = vapply(.data$model, set_of, character(1)))
  # Each set is compared with the best of its selectable candidates; Other with the best IID + year one.
  cvt$ref <- vapply(cvt$set, function(g) {
    if (is.na(g)) return(NA_character_)
    stage_best(res, stage_selectable(res, cvt$model, if (g == "Other") "IID + year" else g))
  }, character(1))
  cvt <- cvt |>
    dplyr::mutate(p = purrr::map2(.data$model, .data$ref, function(m, r) stage_pair(res, m, r)),
                  d = vapply(.data$p, `[[`, numeric(1), "d"),
                  se = vapply(.data$p, `[[`, numeric(1), "se"))
  sets <- setdiff(unique(stats::na.omit(cvt$set)), "Other")
  selectable <- unlist(lapply(sets, function(g) stage_selectable(res, cvt$model, g)))
  elig <- unlist(lapply(sets, function(g) stage_eligible(res, stage_selectable(res, cvt$model, g))))
  cvt$eligible <- ifelse(cvt$model %in% selectable, cvt$model %in% elig, NA)
  role <- function(m) {
    r <- c(if (m == inc) "incoming", if (m == sel) "selected", if (!is.na(smo) && m == smo) "selected, smoothed index")
    if (length(r)) paste0(" (", paste(r, collapse = "; "), ")") else ""
  }
  mard <- vapply(res$table$model, function(m) index_mard(res$index[[m]], res$index[[inc]]), numeric(1))
  out <- res$table |>
    dplyr::mutate(mard = mard, failed = is.na(.data$AIC),
                  set = vapply(.data$model, set_of, character(1))) |>
    dplyr::left_join(dplyr::select(cvt, "model", "d", "se", "eligible"), by = "model") |>
    # By set (random-field stage), then best ELPD first; candidates without CV by AIC.
    dplyr::arrange(match(.data$set, c("IID + year", "Smoothed", "Other", "All")),
                   is.na(.data$d), dplyr::desc(.data$d), .data$AIC) |>
    dplyr::transmute(
      Candidate = paste0(.data$model, vapply(.data$model, role, character(1)),
                         ifelse(.data$failed, " (no fit saved)", "")),
      Set = .data$set,
      Converged = ifelse(.data$failed, NA, .data$converged),
      `Hessian PD` = ifelse(.data$failed, NA, .data$pdHess),
      Sanity = ifelse(.data$failed, NA, .data$sanity),
      `ΔAIC` = round(.data$deltaAIC, 1),
      `ΔELPD` = round(.data$d, 1), `SE(Δ)` = round(.data$se, 1),
      `≤ 1 SE of best` = ifelse(is.na(.data$d), NA, .data$eligible),
      `MARD (%)` = round(100 * .data$mard, 1)
    )
  if (!fields) out$Set <- NULL
  out
}

# IID spatiotemporal fields with a year factor (the structure of an index for a state-space assessment such as SPiCT), from a stage spec.
is_iid_year_spec <- function(x) {
  st <- unlist(x$spatiotemporal)
  isTRUE(x$year) && all(st %in% c("iid", "off")) && any(st == "iid")
}

# Smoothed-index structure: AR1 or random-walk spatiotemporal fields without a year factor.
is_smoothed_spec <- function(x) {
  !isTRUE(x$year) && is_smoothed_set_spec(x)
}

# AR1 or random-walk spatiotemporal fields, with or without a year factor: the Smoothed set.
is_smoothed_set_spec <- function(x) all(unlist(x$spatiotemporal) %in% c("ar1", "rw"))

# Parameters of a smoothed structure, for the parsimony rule: one per random field (a variance)
# and half a field for each AR1 correlation, so a random walk is simpler than an AR1 field and
# a model without the spatial field simpler than one with it.
smooth_size_spec <- function(x) {
  per <- function(v) if (is.list(v)) unlist(v) else rep(v, 2)
  st <- per(x$spatiotemporal)
  sum(per(x$spatial) != "off") + sum(st != "off") + 0.5 * sum(st == "ar1")
}

# Plain-language account of a stage's decision: the incoming model, the best candidate by
# cross-validation, the selected model and the rule that selected it, and the candidates that
# cross-validation cannot tell apart from the selected one.
stage_summary <- function(res) {
  if (is.null(res)) return("This stage has not been run yet.")
  inc <- stage_incoming(res); sel <- res$carried; best <- res$best_cv
  cvm <- res$cv$model
  vs_inc <- function(m) fmt_pair(stage_pair(res, m, inc))
  rule <- switch(res$stage,
    fields = {
      if (sel == best) {
        "it has the highest ELPD and is an IID + year structure."
      } else {
        paste0(if (stage_set(res, best) != "IID + year") paste0("the best candidate, ", best, ", has no IID spatiotemporal field with a year factor, which the index for a state-space assessment model needs; ") else "",
               "among the IID + year candidates within one paired SE of the best of them, the selected one has the fewest random fields.")
      }
    },
    geometry = if (sel == inc) {
      "the isotropic model, the simplest geometry, is within one paired SE of the best."
    } else {
      paste0("the isotropic model is more than one paired SE below it (ΔELPD ", vs_inc(sel), ").")
    },
    fixed = "it is the simplest candidate within one paired SE of the best.",
    family = {
      tw <- names(res$specs)[vapply(res$specs, function(x) identical(x$family, "tweedie"), logical(1))]
      tw_cv <- length(tw) && tw %in% cvm
      if (length(tw) && sel == tw) {
        "the Tweedie family, the simplest (one model component instead of two), is within one paired SE of the best."
      } else {
        paste0("it has the highest ELPD; the delta families have the same number of parameters, so parsimony cannot choose among them, ",
               if (tw_cv) "and the Tweedie family, the only simpler one, is more than one paired SE below the best." else "and the Tweedie family, the only simpler one, was not cross-validated in this run.")
      }
    },
    "")
  close <- setdiff(cvm, sel)
  close <- close[vapply(close, function(m) stage_set(res, m) == stage_set(res, sel), logical(1))]
  close <- close[vapply(close, function(m) {
    p <- stage_pair(res, m, sel); !is.na(p[["d"]]) && abs(p[["d"]]) <= p[["se"]]
  }, logical(1))]
  smo <- stage_smoothed(res)
  smo_txt <- if (!identical(res$stage, "fields")) "" else if (is.na(smo)) {
    " No smoothed candidate was cross-validated in this run, so the smoothed-index structure is selected when the stage is rerun."
  } else {
    smo_best <- stage_best(res, stage_selectable(res, cvm, "Smoothed"))
    paste0(" For the smoothed index, the selected structure is **", smo, "**, the smoothed candidate with the fewest parameters within one paired SE of the best smoothed candidate",
           if (smo != smo_best) paste0(", ", smo_best, " (ΔELPD ", fmt_pair(stage_pair(res, smo, smo_best)), ")") else "",
           ". The later stages select the fixed effects, the geometry and the family on the IID model; the smoothed index uses them with this field structure.")
  }
  paste0(
    "The incoming model is **", inc, "**. ",
    "Cross-validation ranked **", best, "** highest",
    if (best != inc) paste0(" (ΔELPD ", vs_inc(best), " relative to the incoming model)") else "", ". ",
    "The selected model is **", sel, "** because ", rule,
    if (length(close)) paste0(" Cross-validation cannot separate it from ",
                              paste0(close, " (ΔELPD ", vapply(close, function(m) fmt_pair(stage_pair(res, m, sel)), ""), ")",
                                     collapse = " or "),
                              ", whose difference from the selected model is smaller than its paired SE.") else "",
    smo_txt)
}

# Indices of the candidates of one stage, relative to their own series mean so that differences
# in level (e.g. between families) do not hide differences in trend.
plot_stage_index <- function(res, relative = TRUE, base_size = 9) {
  idx <- purrr::imap_dfr(res$index, function(x, nm) if (is.null(x)) NULL else dplyr::mutate(x, model = nm))
  if (!nrow(idx)) return(NULL)
  if (relative) {
    idx <- idx |> dplyr::group_by(.data$model) |>
      dplyr::mutate(m = mean(.data$est), est = .data$est / .data$m,
                    lwr = .data$lwr / .data$m, upr = .data$upr / .data$m) |>
      dplyr::ungroup()
  }
  idx$selected <- idx$model == res$carried
  ggplot2::ggplot(idx, ggplot2::aes(.data$year, .data$est, colour = .data$model)) +
    ggplot2::geom_ribbon(data = dplyr::filter(idx, .data$selected),
                         ggplot2::aes(ymin = .data$lwr, ymax = .data$upr), fill = "grey80",
                         colour = NA, alpha = 0.6) +
    ggplot2::geom_line(ggplot2::aes(linewidth = .data$selected)) +
    ggplot2::scale_linewidth_manual(values = c(`TRUE` = 1.1, `FALSE` = 0.45), guide = "none") +
    ggplot2::labs(x = "Year", y = if (relative) "Index / series mean" else "Index (kg)", colour = NULL) +
    ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(legend.position = "bottom") +
    ggplot2::guides(colour = ggplot2::guide_legend(ncol = 2))
}

describe_spec <- function(d) {
  f <- function(x) if (is.list(x)) paste(unlist(x), collapse = "/") else x
  paste0("terms: ", paste(c(if (d$year) "fyear", d$terms), collapse = " + "),
         if (!is.null(d$positive_terms)) paste0(" (positive part: ", paste(d$positive_terms, collapse = " + "), ")") else "",
         "; spatial: ", f(d$spatial), "; spatiotemporal: ", f(d$spatiotemporal),
         "; family: ", d$family, "; mesh: ", d$mesh_km, " km",
         if (isTRUE(d$anisotropy)) "; anisotropic" else "",
         if (isTRUE(d$barrier)) "; barrier mesh" else "")
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
