# cpue_helpers.R — project-side helpers for commercial CPUE indices (docs/sdmtmb/cpue).
# Record preparation (vessel activity and identity, filter cascade, landings reconciliation),
# prediction references, indices from glmmTMB, mgcv and sdmTMB fits, AIC on the catch scale,
# grouped residual dispersion and the vessel bootstrap. See knowledge/cpue.md and
# knowledge/cpue-models.md. Column names follow the record schema of the CPUE document:
# year, vessel_id, catch, effort, and optional covariates.

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- Records ----------------------------------------------------------------------------
# Per-vessel activity: years active, first/last year, share of years active within the period
# of participation, and records per year and in total. The core-fleet filters use these.
cpue_vessel_activity <- function(d, vessel = "vessel_id", year = "year") {
  d |>
    dplyr::group_by(.data[[vessel]]) |>
    dplyr::mutate(
      first_year = min(.data[[year]]),
      last_year = max(.data[[year]]),
      years_active = dplyr::n_distinct(.data[[year]]),
      active_prop = years_active / (last_year - first_year + 1),
      records_total = dplyr::n()
    ) |>
    dplyr::group_by(.data[[vessel]], .data[[year]]) |>
    dplyr::mutate(records_year = dplyr::n()) |>
    dplyr::ungroup()
}

# A vessel replaced under the same identifier: from the first year in which its length departs
# from its first year's median length by more than `tol` (m), records get a new identifier.
# One change per vessel is handled; check the returned `vessel_changed` flag for more.
cpue_vessel_changes <- function(d, vessel = "vessel_id", year = "year",
                                size = "vessel_length", tol = 2) {
  changes <- d |>
    dplyr::group_by(.data[[vessel]]) |>
    dplyr::mutate(.ref = stats::median(.data[[size]][.data[[year]] == min(.data[[year]])],
                                       na.rm = TRUE)) |>
    dplyr::filter(abs(.data[[size]] - .ref) > tol) |>
    dplyr::summarise(.change_year = min(.data[[year]]), .groups = "drop")
  d |>
    dplyr::left_join(changes, by = vessel) |>
    dplyr::mutate(
      vessel_changed = !is.na(.change_year),
      vessel_id_original = .data[[vessel]],
      !!vessel := factor(ifelse(vessel_changed & .data[[year]] >= .change_year,
                                paste0(.data[[vessel]], "_new"),
                                as.character(.data[[vessel]])))
    ) |>
    dplyr::select(-".change_year")
}

# Apply named filter steps in order and log what each removes. `steps` is a named list of
# quoted expressions, e.g. list("positive catch" = quote(catch > 0)). Every threshold in it
# belongs in config.yaml and in a sensitivity run.
cpue_filter_cascade <- function(d, steps, vessel = "vessel_id", catch = "catch") {
  log_row <- function(x, step) data.frame(
    step = step, records = nrow(x), vessels = dplyr::n_distinct(x[[vessel]]),
    catch = sum(x[[catch]], na.rm = TRUE))
  out <- list(log_row(d, "all records"))
  for (nm in names(steps)) {
    d <- dplyr::filter(d, !!steps[[nm]])
    out[[length(out) + 1]] <- log_row(d, nm)
  }
  log <- dplyr::bind_rows(out) |>
    dplyr::mutate(records_share = records / records[1], catch_share = catch / catch[1])
  list(data = d, log = log)
}

# Logbook catch against landed catch per year. A low or falling coverage means the index
# describes a small or shrinking part of the fleet.
cpue_reconcile <- function(d, landings, year = "year", catch = "catch", landed = "landed") {
  dplyr::full_join(
    d |> dplyr::group_by(.data[[year]]) |>
      dplyr::summarise(logbook_catch = sum(.data[[catch]], na.rm = TRUE), .groups = "drop"),
    landings |> dplyr::group_by(.data[[year]]) |>
      dplyr::summarise(landed_catch = sum(.data[[landed]], na.rm = TRUE), .groups = "drop"),
    by = year
  ) |>
    dplyr::mutate(coverage = logbook_catch / landed_catch) |>
    dplyr::arrange(.data[[year]])
}

# Nominal CPUE per year, as a reference only: ratio of sums and mean of ratios.
cpue_nominal <- function(d, year = "year", catch = "catch", effort = "effort") {
  d |>
    dplyr::group_by(.data[[year]]) |>
    dplyr::summarise(ratio_of_sums = sum(.data[[catch]]) / sum(.data[[effort]]),
                     mean_of_ratios = mean(.data[[catch]] / .data[[effort]]),
                     records = dplyr::n(), .groups = "drop") |>
    dplyr::mutate(index = ratio_of_sums / mean(ratio_of_sums))
}

# --- Prediction references --------------------------------------------------------------
# One row per year at reference conditions. `reference` names the value of each covariate (a
# number, a factor level, or NULL for the median of a numeric column / the most common level of
# a factor). Grouping columns of random effects are set to NA, i.e. population level.
cpue_newdata <- function(d, reference, groups = "vessel_id", year = "year",
                         year_factor = "fyear") {
  nd <- d |>
    dplyr::distinct(.data[[year]], .data[[year_factor]]) |>
    dplyr::arrange(.data[[year]])
  for (v in names(reference)) {
    x <- d[[v]]
    value <- reference[[v]] %||%
      (if (is.numeric(x)) stats::median(x, na.rm = TRUE) else names(which.max(table(x))))
    nd[[v]] <- if (is.factor(x)) factor(value, levels = levels(x)) else value
  }
  for (g in groups) nd[[g]] <- if (is.factor(d[[g]])) factor(NA, levels = levels(d[[g]])) else NA
  nd
}

# For mgcv, a random-effect smooth needs a valid level in newdata even when it is excluded.
.fill_group_levels <- function(newdata, fit, groups) {
  for (g in groups) {
    if (g %in% names(newdata) && anyNA(newdata[[g]])) {
      lev <- levels(fit$model[[g]]) %||% levels(factor(fit$model[[g]]))
      newdata[[g]] <- factor(lev[1], levels = lev)
    }
  }
  newdata
}

.relative <- function(est, lwr, upr) {
  m <- mean(est)
  data.frame(index = est / m, index_lwr = lwr / m, index_upr = upr / m)
}

# --- Indices from fits ------------------------------------------------------------------
# Year index from a non-spatial (or area-factor) model: the prediction at reference conditions
# per year, population level (random effects excluded). glmmTMB: re.form = NA. mgcv: the
# random-effect smooths named in `exclude` are dropped. `se` is on the log scale. `newdata`
# must carry every model covariate; for a model with a spatial smooth that means a reference
# location, so use cpue_gam_area_index() there instead.
cpue_year_index <- function(fit, newdata, exclude = NULL, groups = "vessel_id", level = 0.95) {
  z <- stats::qnorm(1 - (1 - level) / 2)
  if (inherits(fit, "glmmTMB")) {
    p <- predict(fit, newdata = newdata, type = "link", se.fit = TRUE, re.form = NA,
                 allow.new.levels = TRUE)
  } else if (inherits(fit, "gam")) {
    p <- predict(fit, newdata = .fill_group_levels(newdata, fit, groups), type = "link",
                 se.fit = TRUE, exclude = exclude, newdata.guaranteed = TRUE)
  } else {
    stop("cpue_year_index() handles glmmTMB and mgcv fits; use cpue_sdm_index() for sdmTMB.")
  }
  out <- data.frame(year = newdata$year, log_est = as.vector(p$fit), se = as.vector(p$se.fit))
  out$est <- exp(out$log_est)
  out$lwr <- exp(out$log_est - z * out$se)
  out$upr <- exp(out$log_est + z * out$se)
  cbind(out, .relative(out$est, out$lwr, out$upr))
}

# Standard error of each glmmTMB year effect relative to the series mean: the precision of the
# trend, without the uncertainty all years share (intercept, reference levels).
cpue_year_contrast_se <- function(fit, pattern = "^fyear") {
  V <- stats::vcov(fit)$cond
  yi <- grep(pattern, colnames(V))
  n <- length(yi)
  L <- diag(n) - matrix(1 / n, n, n)
  sqrt(diag(L %*% V[yi, yi, drop = FALSE] %*% t(L)))
}

# Area-weighted index from an mgcv model with a spatial smooth: predict every grid cell (one
# row per cell and year) at reference conditions, sum density x cell area per year, and take
# intervals from `nsim` draws of the coefficients (Bayesian posterior covariance Vp).
cpue_gam_area_index <- function(fit, grid, area = 1, exclude = NULL, groups = "vessel_id",
                                nsim = 500, level = 0.95, seed = 1) {
  grid <- .fill_group_levels(grid, fit, groups)
  X <- predict(fit, newdata = grid, type = "lpmatrix", exclude = exclude,
               newdata.guaranteed = TRUE)
  beta <- stats::coef(fit)
  set.seed(seed)
  R <- chol(fit$Vp)
  draws <- matrix(stats::rnorm(nsim * length(beta)), nsim) %*% R
  draws <- sweep(draws, 2, beta, "+")
  area <- rep_len(area, nrow(grid))
  year_of <- grid$year
  totals <- function(b) tapply(exp(drop(X %*% b)) * area, year_of, sum)
  est <- totals(beta)
  sims <- vapply(seq_len(nsim), function(i) totals(draws[i, ]), numeric(length(est)))
  a <- (1 - level) / 2
  out <- data.frame(year = as.numeric(names(est)), est = as.vector(est),
                    lwr = apply(sims, 1, stats::quantile, a),
                    upr = apply(sims, 1, stats::quantile, 1 - a),
                    se = apply(log(sims), 1, stats::sd))
  out$log_est <- log(out$est)
  cbind(out, .relative(out$est, out$lwr, out$upr))
}

# Area-weighted index from an sdmTMB model on a prediction grid of the fished domain: the vessel
# random intercept is dropped (re_form_iid = ~0) and the offset, if any, is 0 (one unit of
# effort). `area` is the cell area or a column name.
cpue_sdm_index <- function(fit, grid, area = 1, bias_correct = FALSE, ...) {
  years <- sort(unique(fit$data[[fit$time]]))
  grid <- grid[grid[[fit$time]] %in% years, , drop = FALSE]
  zero <- rep(0, nrow(grid))
  if ("newdata" %in% names(formals(sdmTMB::get_index))) {
    out <- sdmTMB::get_index(fit, newdata = grid, offset = zero, area = area,
                             bias_correct = bias_correct,
                             predict_args = list(re_form_iid = ~0), ...)
  } else {
    p <- predict(fit, newdata = grid, return_tmb_object = TRUE, offset = zero, re_form_iid = ~0)
    out <- sdmTMB::get_index(p, area = area, bias_correct = bias_correct, ...)
  }
  names(out)[names(out) == fit$time] <- "year"
  cbind(out, .relative(out$est, out$lwr, out$upr))
}

# --- Selection and diagnostics ----------------------------------------------------------
# AIC on the scale of the catch, so that log(CPUE), CPUE and catch responses compare. For
# y = log(catch / effort), log f(catch) = log f(y) - log(catch); for y = catch / effort,
# log f(catch) = log f(y) - log(effort). Valid for continuous families on the same records.
cpue_aic_catch_scale <- function(fit, d, response = c("log_cpue", "cpue", "catch"),
                                 catch = "catch", effort = "effort") {
  response <- match.arg(response)
  jacobian <- switch(response,
    log_cpue = sum(log(d[[catch]])),
    cpue = sum(log(d[[effort]])),
    catch = 0)
  stats::AIC(fit) + 2 * jacobian
}

# Residual dispersion of records aggregated by group (vessel-year, area-year, ...). Records
# sharing a group the model does not contain are correlated: summed over the group, their
# residuals vary more than simulated (dispersion > 1), and the index intervals are too narrow.
# Groups the model does contain serve as controls (dispersion ~ 1). Needs DHARMa.
cpue_dharma_groups <- function(fit, groups, n_sim = 250, seed = 1) {
  set.seed(seed)
  sim <- DHARMa::simulateResiduals(fit, n = n_sim)
  dplyr::bind_rows(lapply(names(groups), function(nm) {
    g <- groups[[nm]]
    r <- if (is.null(g)) sim else DHARMa::recalculateResiduals(sim, group = g)
    t <- DHARMa::testDispersion(r, plot = FALSE)
    data.frame(grouping = nm,
               groups = if (is.null(g)) stats::nobs(fit) else dplyr::n_distinct(g),
               dispersion = unname(t$statistic), p = t$p.value)
  }))
}

# The same question without simulation, for any engine with Pearson residuals (glmmTMB, mgcv,
# sdmTMB): for groups g of size n_g, mean(S_g^2 / n_g) / mean(r^2), with S_g the group's sum of
# residuals. About 1 for independent records, > 1 for records correlated within the group.
# Conditional residuals of groups the model contains are shrunk, so those read <= 1.
cpue_pearson_groups <- function(fit, groups) {
  r <- stats::residuals(fit, type = "pearson")
  base <- mean(r^2, na.rm = TRUE)
  dplyr::bind_rows(lapply(names(groups), function(nm) {
    g <- groups[[nm]]
    s <- tapply(r, g, sum, na.rm = TRUE)
    n <- tapply(!is.na(r), g, sum)
    data.frame(grouping = nm, groups = length(s), median_size = stats::median(n),
               dispersion = mean(s^2 / n) / base)
  }))
}

# Cluster bootstrap over vessels: vessels are drawn with replacement (within `strata` if
# given, e.g. each vessel's main area), each keeping all its records under a new identifier,
# and `fit_index(data)` refits the model and returns a data frame with `year` and `est`. The
# spread of the bootstrap indices does not rely on the model's assumptions about correlation
# within vessels.
cpue_vessel_bootstrap <- function(d, fit_index, n_boot = 200, vessel = "vessel_id",
                                  strata = NULL, seed = 1) {
  rows <- split(seq_len(nrow(d)), as.character(d[[vessel]]))
  pools <- if (is.null(strata)) list(names(rows)) else split(names(rows), strata[names(rows)])
  res <- lapply(seq_len(n_boot), function(b) {
    set.seed(seed + b)
    v <- unlist(lapply(pools, function(p) p[sample.int(length(p), replace = TRUE)]),
                use.names = FALSE)
    db <- d[unlist(rows[v]), , drop = FALSE]
    db[[vessel]] <- factor(rep(paste0(v, "_", seq_along(v)), lengths(rows[v])))
    idx <- tryCatch(fit_index(db), error = function(e) NULL)
    if (is.null(idx)) return(NULL)
    data.frame(boot = b, year = idx$year, est = idx$est, index = idx$est / mean(idx$est))
  })
  out <- dplyr::bind_rows(res)
  attr(out, "n_failed") <- sum(vapply(res, is.null, logical(1)))
  out
}
