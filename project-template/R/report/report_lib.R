# Final survey-index models and their sensitivity analyses for the report documents
# (<DOCS_DIR>/sdmtmb/<stock>/<stock>-6-report.qmd). Every slow step runs on a server as its own
# process and caches its result in data/output/<stock>/report/, which the report reads:
#
#   Rscript R/report/report_compute.R <species> grid
#   Rscript R/report/report_compute.R <species> fit <total-iid|fishable-iid|total-ar1>
#   Rscript R/report/report_compute.R <species> post <total-iid|fishable-iid|total-ar1>
#   Rscript R/report/report_compute.R <species> index-bc <total-iid|fishable-iid|total-ar1>
#   Rscript R/report/report_compute.R <species> retro <total-iid|fishable-iid> [n_workers]
#   Rscript R/report/report_compute.R <species> surveys [n_workers]
#   Rscript R/report/report_compute.R <species> loso [n_workers]
#   Rscript R/report/report_compute.R <species> influence [n_workers]
#   Rscript R/report/report_compute.R <species> sens <name>   # a SENSITIVITIES entry
#   Rscript R/report/report_compute.R <species> sens-names    # list the configured names
#   R/report/run_report.sh <species>          # all steps, in dependency order
#
# The model specification comes from config.yaml: FINAL_MODEL, the specification selected in
# <stock>-5-validate.qmd (without it, the config defaults with IID spatiotemporal fields), and SMOOTHED_*
# for the smoothed index. The final indices (index-bc step) are bias-corrected; the
# diagnostics and sensitivity analyses use indices without bias correction.

#' Shared settings of the report: model data, products and model settings
#'
#' @param cfg Species configuration from R/0_setup.R.
#' @param out_dir Species output folder.
#' @param crs Projected CRS of the model coordinates.
#' @return A list with the configuration (`cfg`), the model data (`dt`, `dt_fishable`), the three `products` (formula,
#'   data, offset, fields and file stem of each), the `family`, the `final` specification, the
#'   `extra_time` years, the cache folder `rep_dir`, and `effort` ("density" or "offset") and
#'   `offset` (offset column or NULL) of the report models.
report_context <- function(cfg, out_dir, crs) {
  # The report's response and offset (report_effort()); the selection compared its candidates
  # with EFFORT (by default the swept-area density).
  effort <- report_effort(cfg, cfg$FINAL_MODEL$FAMILY %||% cfg$FAMILY)
  cfg_eff <- cfg
  cfg_eff$EFFORT <- effort
  dt <- load_model_data(cfg_eff, out_dir, crs)
  offset <- offset_column(cfg_eff)
  final <- cfg$FINAL_MODEL %||% list(
    MESH_CUTOFF_KM = cfg$MESH_CUTOFF_KM, FAMILY = cfg$FAMILY, SPATIAL = cfg$SPATIAL %||% "on",
    SPATIOTEMPORAL = "iid", ANISOTROPY = FALSE,
    TERMS = model_terms(cfg, has_multiple_gears = dplyr::n_distinct(dt$geartype) > 1, data = dt))
  if (is.null(cfg$FINAL_MODEL)) warning("config.yaml has no FINAL_MODEL: the report uses the config defaults, not a selected specification.")
  final$MESH_CUTOFF_KM <- as.numeric(final$MESH_CUTOFF_KM)
  # Cruise numbers are reused by different vessels: a cruise is a platform and a cruise number.
  dt$cruise_id <- paste(dt$platformname, dt$cruise)
  years <- sort(unique(dt$year))
  pos_year <- dt |>
    dplyr::group_by(.data$year) |>
    dplyr::summarise(hauls = dplyr::n(), total = sum(.data$value > 0),
                     fishable = sum(.data$value_fishable > 0), .groups = "drop")
  years_no_fishable <- pos_year$year[pos_year$fishable %in% 0]
  dt_fishable <- dplyr::filter(dt, !.data$year %in% years_no_fishable) |>
    dplyr::mutate(value = .data$value_fishable, fyear = droplevels(.data$fyear),
                  fmonth = droplevels(.data$fmonth))
  term_txt <- paste(final$TERMS, collapse = " + ")
  form_year <- stats::as.formula(paste("value ~ 0 + fyear +", term_txt))
  form_smooth <- stats::as.formula(paste("value ~ 0 +", term_txt))
  as_component <- function(x) if (length(x) == 1L) x[[1]] else as.list(unlist(x))
  products <- list(
    "Total biomass (IID)" = list(file = "total-iid", data = dt, formula = form_year, offset = offset,
                                 spatial = as_component(final$SPATIAL),
                                 spatiotemporal = as_component(final$SPATIOTEMPORAL)),
    "Fishable biomass (IID)" = if (any(!is.na(dt$value_fishable))) {
      list(file = "fishable-iid", data = dt_fishable, formula = form_year, offset = offset,
           spatial = as_component(final$SPATIAL), spatiotemporal = as_component(final$SPATIOTEMPORAL))
    },
    "Total biomass (smoothed)" = list(file = "total-ar1", data = dt, formula = form_smooth, offset = offset,
                                      spatial = as_component(cfg$SMOOTHED_SPATIAL %||% "off"),
                                      spatiotemporal = as_component(cfg$SMOOTHED_SPATIOTEMPORAL %||% "ar1"))
  )
  products <- purrr::compact(products)
  rep_dir <- file.path(out_dir, "report")
  dir.create(rep_dir, showWarnings = FALSE, recursive = TRUE)
  list(cfg = cfg, dt = dt, dt_fishable = dt_fishable, pos_year = pos_year, years = years,
       years_no_fishable = years_no_fishable, products = products, final = final,
       family = report_family(final$FAMILY), form_year = form_year, form_smooth = form_smooth,
       extra_time = setdiff(seq(min(dt$year), max(dt$year)), years), rep_dir = rep_dir,
       effort = effort, offset = offset)
}

#' sdmTMB family object from the FINAL_MODEL family name
#'
#' @param x Family name as in config.yaml.
#' @return An sdmTMB family.
report_family <- function(x) {
  switch(x,
    delta_lognormal = sdmTMB::delta_lognormal(),
    delta_gamma = sdmTMB::delta_gamma(),
    delta_lognormal_poisson_link = sdmTMB::delta_lognormal(type = "poisson-link"),
    delta_gamma_poisson_link = sdmTMB::delta_gamma(type = "poisson-link"),
    tweedie = sdmTMB::tweedie(),
    stop("Unknown FINAL_MODEL$FAMILY: ", x))
}

#' Fit one product
#'
#' The settings are injected as values, so that `fit$call` can be re-evaluated by the refit
#' helpers of sdmTMBexperiments (leave-one-out, survey comparison) in a fresh session.
#'
#' @param s Product from `report_context()$products`; `s$data` may be replaced (retrospective,
#'   sensitivity refits), and `s$family` and `s$offset` override the report family and offset
#'   (`s$offset = FALSE`: no offset).
#' @param ctx Report context.
#' @param mesh Optional mesh; by default a new mesh with the FINAL_MODEL cutoff.
#' @return A fitted sdmTMB model with the fit time (minutes) in `attr(, "fit_minutes")`.
fit_report_product <- function(s, ctx, mesh = NULL) {
  check_temporal_terms(s$formula, s$spatiotemporal)
  m <- mesh %||% sdmTMB::make_mesh(s$data, xy_cols = c("X", "Y"), cutoff = ctx$final$MESH_CUTOFF_KM)
  yrs <- seq(min(s$data$year), max(s$data$year))
  gaps <- setdiff(yrs, unique(s$data$year))
  dyn <- any(unlist(s$spatiotemporal) %in% c("ar1", "rw")) && length(gaps)
  t0 <- Sys.time()
  fit <- rlang::inject(sdmTMB::sdmTMB(
    !!s$formula, data = s$data, mesh = m,
    family = !!(s$family %||% ctx$family), offset = !!(if (isFALSE(s$offset)) NULL else s$offset %||% ctx$offset),
    spatial = !!s$spatial, spatiotemporal = !!s$spatiotemporal,
    anisotropy = !!isTRUE(ctx$final$ANISOTROPY), time = "year",
    extra_time = !!(if (dyn) gaps else NULL),
    control = sdmTMB::sdmTMBcontrol(newton_loops = 1)
  ))
  attr(fit, "fit_minutes") <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  fit
}

#' Guard the report caches against a changed specification or changed data
#'
#' The report steps skip any result whose cache file exists, and the influence step reuses
#' earlier refits, so caches made with another FINAL_MODEL, grid or model data would be
#' silently mixed with new results. The first step writes a stamp of the inputs; every later
#' step stops if the stamp differs (knowledge/pipeline.md).
#'
#' @param ctx Report context.
#' @param cfg Stock configuration.
#' @return The stamp (invisibly); stops when the cached stamp differs.
report_check_stamp <- function(ctx, cfg) {
  stamp <- list(final = ctx$final, effort = ctx$effort, grid_km = cfg$GRID_KM, max_depth = cfg$MAX_DEPTH,
                reference = list(cfg$REFERENCE_MONTH, cfg$REFERENCE_SURVEY,
                                 cfg[["REFERENCE_GEAR", exact = TRUE]], cfg$REFERENCE_GEAR_MODEL),
                smoothed = list(cfg$SMOOTHED_SPATIAL, cfg$SMOOTHED_SPATIOTEMPORAL),
                fishable_year = cfg$FISHABLE_YEAR_EFFECT,
                hauls = digest_strings(ctx$dt$haul_id),
                values = digest_strings(c(ctx$dt$value, ctx$dt$value_fishable)))
  f <- report_cache(ctx, "spec-stamp")
  if (!file.exists(f)) {
    saveRDS(stamp, f)
  } else if (!identical(readRDS(f), stamp)) {
    stop("The caches in ", ctx$rep_dir, " were made with another specification or other model ",
         "data. Move the folder away (or delete it) and rerun R/report/run_report.sh.")
  }
  invisible(stamp)
}

# MD5 of the values written as text: the same on every machine and R version. A hash of a
# serialised R object (rlang::hash(), digest() with serialize = TRUE) is not
# (knowledge/pipeline.md).
digest_strings <- function(x) {
  f <- tempfile()
  on.exit(unlink(f))
  writeLines(format(x, digits = 15, trim = TRUE), f, useBytes = TRUE)
  unname(tools::md5sum(f))
}

# A fit passes when every sanity check passes, or when the only failure is a collapsed smooth
# (sanity_collapsed_smooth(), R/report_helpers.R).
report_passes <- function(fit) {
  if (is.null(fit)) return(FALSE)
  san <- suppressMessages(sdmTMB::sanity(fit, silent = TRUE))
  isTRUE(san$all_ok) ||
    sanity_collapsed_smooth(san, purrr::map_dfr(seq_len(1 + isTRUE(fit$family$delta)), function(k) {
      suppressMessages(sdmTMB::tidy(fit, "ran_pars", model = k))
    }))
}

report_fit_file <- function(ctx, file) file.path(ctx$rep_dir, paste0("fit-", file, ".rds"))
report_cache <- function(ctx, name) file.path(ctx$rep_dir, paste0(name, ".rds"))
read_report_cache <- function(ctx, name) {
  f <- report_cache(ctx, name)
  if (file.exists(f)) readRDS(f)
}

#' Prediction grid of the report (GRID_KM cells), with the ICES division of each cell and, when
#' REGIONS_FILE is set, the assessment region
#'
#' @param ctx Report context.
#' @param cfg Species configuration.
#' @param crs Projected CRS.
#' @return The grid (all years), cached in the report folder.
report_grid <- function(ctx, cfg, crs) {
  f <- report_cache(ctx, "prediction-grid")
  if (file.exists(f)) return(readRDS(f))
  region <- read_prediction_region(cfg, crs)
  if (is.null(region)) stop("No prediction region: render the <stock>-3-data document first.")
  grid <- build_model_grid(region, ctx$dt, cfg)
  cells <- unique(grid[c("X", "Y")])
  cells$division <- ices_division(cells, cfg, crs)
  cells$region <- assessment_region(cells, cfg, crs)
  grid <- dplyr::left_join(grid, cells, by = c("X", "Y"))
  saveRDS(grid, f)
  grid
}

#' ICES division of points in model coordinates (km)
#'
#' Uses the ICES polygons the survey selection uses (ICES_AREAS_FILE), so that the divisions
#' agree with the area codes of the hauls. Points on a boundary gap go to the nearest polygon.
#'
#' @param xy Data frame with X and Y (km) in `crs`.
#' @param cfg Species configuration.
#' @param crs Projected CRS.
#' @return Character vector of divisions such as "1.b" and "2.a".
ices_division <- function(xy, cfg, crs) {
  old <- sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old))
  areas <- read_ices_area_polygons(cfg) |>
    (\(x) if (is.null(cfg$REPORT_SUBAREAS)) x else dplyr::filter(x, .data$SubArea %in% unlist(cfg$REPORT_SUBAREAS)))() |>
    dplyr::mutate(division = paste(.data$SubArea, .data$Division, sep = ".")) |>
    dplyr::group_by(.data$division) |>
    dplyr::summarise(.groups = "drop") |>
    sf::st_transform(crs)
  pts <- sf::st_as_sf(data.frame(x = xy$X * 1000, y = xy$Y * 1000), coords = c("x", "y"), crs = crs)
  areas$division[sf::st_nearest_feature(pts, areas)]
}

read_ices_area_polygons <- function(cfg) read_ices_areas(cfg)

#' Areas of the regional split (REGIONS_FILE with a `region` column), in model coordinates
#'
#' Without REGIONS_FILE the ICES divisions of the stock area are the regions.
#'
#' @param cfg Stock configuration; `REGIONS` gives the regions to keep and their order (all
#'   regions of the file when NULL).
#' @param crs Projected CRS.
#' @return An sf object with a factor column `region`.
read_assessment_regions <- function(cfg, crs) {
  old <- sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old))
  x <- if (is.null(cfg$REGIONS_FILE)) {
    read_ices_area_polygons(cfg) |>
      (\(a) if (is.null(cfg$REPORT_SUBAREAS)) a else dplyr::filter(a, .data$SubArea %in% unlist(cfg$REPORT_SUBAREAS)))() |>
      dplyr::mutate(region = paste(.data$SubArea, .data$Division, sep = ".")) |>
      dplyr::group_by(.data$region) |>
      dplyr::summarise(.groups = "drop")
  } else sf::read_sf(here::here(cfg$REGIONS_FILE))
  lev <- unlist(cfg$REGIONS) %||% sort(unique(x$region))
  x |>
    dplyr::filter(.data$region %in% lev) |>
    sf::st_make_valid() |>
    sf::st_transform(crs) |>
    dplyr::mutate(region = factor(.data$region, levels = lev))
}

#' Assessment region of points in model coordinates (km); points outside go to the nearest
#'
#' @param xy Data frame with X and Y (km) in `crs`.
#' @param cfg Stock configuration.
#' @param crs Projected CRS.
#' @return Factor of regions.
assessment_region <- function(xy, cfg, crs) {
  regions <- read_assessment_regions(cfg, crs)
  pts <- sf::st_as_sf(data.frame(x = xy$X * 1000, y = xy$Y * 1000), coords = c("x", "y"), crs = crs)
  regions$region[sf::st_nearest_feature(pts, regions)]
}

# --- Products -------------------------------------------------------------------------------

#' Product specification without the year factor
#'
#' Without the year factor only the spatiotemporal fields carry the change between years, so the
#' model takes the field structure selected for models without a year factor (the smoothed
#' index). The IID structure of the total model can leave a component with no temporal term at
#' all (IID in the positive component only gave a flat fishable index for ling, 2026-11-26).
#'
#' @param s Product specification (element of `ctx$products`).
#' @param ctx Report context.
#' @return The specification with the formula and the fields of the smoothed index.
report_no_year_spec <- function(s, ctx) {
  sm <- ctx$products[["Total biomass (smoothed)"]]
  s$formula <- ctx$form_smooth
  s$spatial <- sm$spatial
  s$spatiotemporal <- sm$spatiotemporal
  s
}

#' Fit one product and cache the model
#'
#' The fishable data are sparse in some years. With `FISHABLE_YEAR_EFFECT: false` in
#' config.yaml the fishable model is fitted without the year factor; otherwise, if the model
#' with the year factor fails the sanity checks, it is refitted without it. Without the year
#' factor it takes the field structure of the smoothed index. Either way the fit
#' is flagged with `attr(, "year_factor_failed")`.
#'
#' @param ctx Report context.
#' @param label Product name.
#' @return The fit (invisibly).
run_report_fit <- function(ctx, label) {
  s <- ctx$products[[label]]
  no_year <- label == "Fishable biomass (IID)" && !isTRUE(ctx$cfg$FISHABLE_YEAR_EFFECT %||% TRUE)
  fit <- if (no_year) NULL else try(fit_report_product(s, ctx))
  if (inherits(fit, "try-error")) fit <- NULL
  if (label == "Fishable biomass (IID)" && !report_passes(fit)) {
    message("Refitting ", label, " without the year factor")
    s <- report_no_year_spec(s, ctx)
    fit2 <- try(fit_report_product(s, ctx))
    if (!inherits(fit2, "try-error")) {
      attr(fit2, "year_factor_failed") <- TRUE
      fit <- fit2
    }
  }
  if (is.null(fit)) stop(label, " failed to fit.")
  saveRDS(fit, report_fit_file(ctx, s$file))
  invisible(fit)
}

#' Everything the report shows about one fitted product
#'
#' @param ctx Report context.
#' @param label Product name.
#' @param grid Report grid.
#' @param nsim Number of simulations from the fitted model.
#' @return A list (cached as post-<file>.rds) with the sanity checks, the index, the fixed and
#'   random parameters, the residuals, simulation summaries, the grid predictions, the
#'   conditional effects and, for the total biomass (IID), the regional index.
run_report_post <- function(ctx, label, grid, nsim = 100) {
  s <- ctx$products[[label]]
  fit <- readRDS(report_fit_file(ctx, s$file))
  san <- suppressMessages(sdmTMB::sanity(fit, silent = TRUE))
  g <- grid_for_fit(grid, fit)
  if ("fmonth" %in% names(g)) g$fmonth <- factor(g$fmonth, levels = levels(fit$data$fmonth))
  t0 <- Sys.time()
  index <- predict_index(fit, g, area = grid_cell_area_nmi2, bias_correct = FALSE)
  index_minutes <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  delta <- isTRUE(fit$family$delta)
  comps <- if (delta) 1:2 else 1
  tidy_comp <- function(effects) {
    dplyr::bind_rows(lapply(comps, function(k) {
      x <- try(sdmTMB::tidy(fit, effects = effects, conf.int = TRUE, model = k), silent = TRUE)
      if (inherits(x, "try-error")) return(NULL)
      dplyr::mutate(tibble::as_tibble(x), component = k)
    }))
  }
  resid <- lapply(comps, function(k) {
    r <- try(stats::residuals(fit, type = "mle-mvn", model = k), silent = TRUE)
    if (inherits(r, "try-error")) NULL else r
  })
  set.seed(1)
  sims <- try(stats::simulate(fit, nsim = nsim, type = "mle-mvn"), silent = TRUE)
  sim_sum <- if (!inherits(sims, "try-error")) simulation_summary(fit$data, sims)
  pred <- suppressMessages(stats::predict(fit, newdata = g, offset = rep(0, nrow(g))))
  keep <- intersect(c("X", "Y", "year", "depth", "division", "est", "est1", "est2", "omega_s",
                      "omega_s1", "omega_s2", "epsilon_st", "epsilon_st1", "epsilon_st2"), names(pred))
  pred <- pred[keep]
  if (delta) pred$est <- delta_log_density(pred, fit)
  ref <- list(year = max(fit$data$year), month = unique(g$month)[1],
              geartype = reference_gear(ctx$dt, cfg), fgear = cfg$REFERENCE_GEAR_MODEL)
  # Only the model's own variables: the trawl-model factor `fgear` takes REFERENCE_GEAR_MODEL
  # (else its most common level); other names would only raise warnings.
  ref <- purrr::compact(ref[intersect(names(ref), names(fit$data))])
  effects <- try(sdmTMBexperiments::conditional_effects(fit, ref = ref), silent = TRUE)
  if (inherits(effects, "try-error")) message("conditional_effects() failed: ", conditionMessage(attr(effects, "condition")))
  region <- if (label == "Total biomass (IID)") {
    index_by_region(fit, newdata = g, region_col = "division", area = grid_cell_area_nmi2)
  }
  out <- list(
    label = label, file = s$file, hauls = nrow(fit$data), positive = sum(fit$data$value > 0),
    formula = deparse1(fit$formula[[1]]),
    converged = fit$model$convergence == 0, max_gradient = max(abs(fit$gradients)),
    pdHess = isTRUE(fit$pos_def_hessian), sanity = san, all_ok = isTRUE(san$all_ok),
    nll = fit$model$objective, aic = stats::AIC(fit), vertices = fit$spde$mesh$n,
    fit_minutes = attr(fit, "fit_minutes"), index_minutes = index_minutes,
    year_factor_failed = isTRUE(attr(fit, "year_factor_failed")),
    index = index, fixed = tidy_comp("fixed"), ran_pars = tidy_comp("ran_pars"),
    resid = resid, sims = sim_sum, pred = pred,
    effects = if (!inherits(effects, "try-error")) effects, region = region
  )
  saveRDS(out, report_cache(ctx, paste0("post-", s$file)))
  invisible(out)
}

#' Bias-corrected index of one product
#'
#' The final indices are computed with the bias correction of the retransformation of the random
#' effects (`bias_correct = TRUE` in `sdmTMB::get_index()`; Thorson and Kristensen 2016). The
#' other results of the report use the uncorrected index of `run_report_post()`.
#'
#' @param ctx Report context.
#' @param label Product name.
#' @param grid Report grid.
#' @return The index (cached as index-bc-<file>.rds) with the fitting time in minutes.
run_report_index_bc <- function(ctx, label, grid) {
  s <- ctx$products[[label]]
  fit <- readRDS(report_fit_file(ctx, s$file))
  g <- grid_for_fit(grid, fit)
  if ("fmonth" %in% names(g)) g$fmonth <- factor(g$fmonth, levels = levels(fit$data$fmonth))
  t0 <- Sys.time()
  index <- predict_index(fit, g, area = grid_cell_area_nmi2, bias_correct = TRUE)
  attr(index, "minutes") <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  saveRDS(index, report_cache(ctx, paste0("index-bc-", s$file)))
  invisible(index)
}

#' Observed and simulated catches, summarised for the predicted-distribution figures
#'
#' @param d Model data (`fit$data`).
#' @param sims Matrix of simulated responses (hauls x simulations).
#' @return A list: `year` (observed and simulated share of zero catches and mean density per
#'   year, with 95 % intervals over simulations), `overall` (the same over all years) and
#'   `haul` (observed and mean simulated density per haul).
simulation_summary <- function(d, sims) {
  q <- function(x) stats::quantile(x, c(0.025, 0.975), na.rm = TRUE, names = FALSE)
  by_year <- lapply(split(seq_len(nrow(d)), d$year), function(i) {
    zero <- colMeans(sims[i, , drop = FALSE] == 0)
    mn <- colMeans(sims[i, , drop = FALSE])
    tibble::tibble(year = d$year[i[1]], obs_zero = mean(d$value[i] == 0),
                   sim_zero = mean(zero), sim_zero_lwr = q(zero)[1], sim_zero_upr = q(zero)[2],
                   obs_mean = mean(d$value[i]), sim_mean = mean(mn), sim_mean_lwr = q(mn)[1],
                   sim_mean_upr = q(mn)[2])
  })
  zero <- colMeans(sims == 0)
  mn <- colMeans(sims)
  list(year = dplyr::bind_rows(by_year),
       overall = tibble::tibble(obs_zero = mean(d$value == 0), sim_zero = mean(zero),
                                sim_zero_lwr = q(zero)[1], sim_zero_upr = q(zero)[2],
                                obs_mean = mean(d$value), sim_mean = mean(mn),
                                sim_mean_lwr = q(mn)[1], sim_mean_upr = q(mn)[2]),
       haul = tibble::tibble(year = d$year, depth = d$depth, obs = d$value,
                             sim = rowMeans(sims), sim_zero = rowMeans(sims == 0)))
}

# --- Sensitivity analyses -------------------------------------------------------------------

#' Drop hauls in factor levels without any positive catch
#'
#' A subset of the data (a retrospective peel, a leave-out refit) can leave a level of a
#' factor covariate with hauls but no positive catch. Its coefficient in the positive
#' component then has no data, and in the encounter component it tends to minus infinity,
#' so the Hessian is not positive definite. Such hauls carry no information on either
#' coefficient beyond "always empty", so they are removed and the level dropped.
#'
#' @param data Model data with the response in `value`.
#' @param cols Factor columns to check.
#' @return `data` without those hauls; the number of removed hauls in `attr(, "n_dropped")`.
drop_empty_levels <- function(data, cols = "fmonth") {
  n0 <- nrow(data)
  for (v in intersect(cols, names(data))) {
    has_pos <- tapply(data$value > 0, data[[v]], any)
    data <- data[as.character(data[[v]]) %in% names(has_pos)[has_pos %in% TRUE], , drop = FALSE]
  }
  data <- droplevels(data)
  attr(data, "n_dropped") <- n0 - nrow(data)
  data
}

#' Retrospective analysis with the year factor re-levelled in each peel
#'
#' `sdmTMBexperiments::sdmTMB_retro()` keeps the removed years as empty levels of a year
#' factor, which leaves their coefficients without data; this version drops them, and the hauls
#' of month levels left without a positive catch (`drop_empty_levels()`). Each peel
#' keeps the mesh of the full model, so the peels differ only in the data.
#'
#' @param ctx Report context.
#' @param label Product name.
#' @param grid Report grid.
#' @param nyears Number of peels including the full model (peel 0).
#' @param n_workers Parallel peels.
#' @return An object of class `sdmTMB_retro` (one element per peel with its `index`), with
#'   the sanity result and fit time of each peel in `attr(, "peels")`.
run_report_retro <- function(ctx, label, grid, nyears = 6, n_workers = 6) {
  s <- ctx$products[[label]]
  fit <- readRDS(report_fit_file(ctx, s$file))
  if (isTRUE(attr(fit, "year_factor_failed"))) s <- report_no_year_spec(s, ctx)
  years <- rev(sort(unique(fit$data$year)))[seq_len(nyears)]
  future::plan(future::multicore, workers = n_workers)
  on.exit(future::plan(future::sequential), add = TRUE)
  res <- future.apply::future_lapply(years, function(k) {
    sk <- s
    sk$data <- drop_empty_levels(fit$data[fit$data$year <= k, , drop = FALSE])
    mesh <- sdmTMB::make_mesh(sk$data, xy_cols = c("X", "Y"), mesh = fit$spde$mesh)
    m <- try(fit_report_product(sk, ctx, mesh = mesh), silent = TRUE)
    if (inherits(m, "try-error")) {
      return(list(index = data.frame(year = sort(unique(sk$data$year)), est = NA_real_,
                                     lwr = NA_real_, upr = NA_real_, se = NA_real_, type = "crashed"),
                  ok = FALSE, minutes = NA_real_, n_dropped = attr(sk$data, "n_dropped")))
    }
    g <- grid_for_fit(grid, m)
    if ("fmonth" %in% names(g)) g$fmonth <- factor(g$fmonth, levels = levels(m$data$fmonth))
    idx <- predict_index(m, g, area = grid_cell_area_nmi2, bias_correct = FALSE)
    idx$type <- "ok"
    list(index = idx, ok = report_passes(m), minutes = attr(m, "fit_minutes"),
         n_dropped = attr(sk$data, "n_dropped"))
  }, future.seed = TRUE)
  out <- lapply(res, function(r) list(index = r$index))
  names(out) <- paste0("peel ", seq_along(years) - 1, ": ", years)
  class(out) <- "sdmTMB_retro"
  attr(out, "peels") <- tibble::tibble(peel = names(out), year = years,
                                       all_ok = vapply(res, `[[`, logical(1), "ok"),
                                       minutes = vapply(res, `[[`, numeric(1), "minutes"),
                                       n_dropped = vapply(res, function(r) as.integer(r$n_dropped %||% 0L), integer(1)))
  saveRDS(out, report_cache(ctx, paste0("retro-", s$file)))
  invisible(out)
}

#' Indices fitted to single survey series, compared with the compiled total biomass index
#'
#' Each survey model has the specification of the compiled total biomass (IID) model: a year
#' factor, a depth smooth, the spatial field and the IID spatiotemporal field of FINAL_MODEL,
#' and the compiled family. The month term is left out, because each series samples one season.
#' The survey indices are therefore comparable with the compiled index year by year and could
#' serve as alternative indices. Years in which a series caught no fish are left out of its
#' model (a year factor cannot be estimated from zeros only). A survey model that fails to fit
#' or does not pass the sanity checks is simplified in steps (`survey_model_ladder()`) until one
#' passes; the step used is recorded.
#'
#' @param ctx Report context.
#' @param grid Report grid.
#' @param surveys Cruise series to compare.
#' @param n_workers Parallel survey fits.
#' @return An `sdmTMB_survey_comparison` object with the attributes `steps` (ladder step of each
#'   survey), `families`, `years_dropped` and `attempts` (every attempt and its outcome).
run_report_surveys <- function(ctx, grid, surveys = cfg$REPORT_SURVEYS, n_workers = 3) {
  fit <- readRDS(report_fit_file(ctx, "total-iid"))
  index <- readRDS(report_cache(ctx, "post-total-iid"))$index
  g <- grid_for_fit(grid, fit)
  if ("fmonth" %in% names(g)) g$fmonth <- factor(g$fmonth, levels = levels(fit$data$fmonth))
  # Default: the three series with most hauls.
  if (is.null(surveys)) surveys <- names(utils::head(sort(table(fit$data$cruiseseries), decreasing = TRUE), 3))
  ladder <- survey_model_ladder(ctx)
  one_survey <- function(sv) {
    d <- fit$data[fit$data$cruiseseries == sv, ]
    pos_years <- sort(unique(d$year[d$value > 0]))
    dropped <- setdiff(sort(unique(d$year)), pos_years)
    attempts <- list()
    best <- NULL
    for (step in names(ladder)) {
      st <- ladder[[step]]
      spec <- sdmTMBexperiments::survey_spec(
        sv, formula = st$formula, family = st$family, spatial = st$spatial,
        spatiotemporal = st$spatiotemporal,
        filter = function(x) droplevels(x[x$year %in% pos_years, , drop = FALSE]))
      comp <- try(sdmTMBexperiments::compare_surveys(
        data = fit$data, compiled_index = index, compiled_model = fit,
        surveys = stats::setNames(list(spec), sv), newdata = g, object_crs = sf::st_crs(dt_crs),
        mesh_cutoff = ctx$final$MESH_CUTOFF_KM, offset_col = ctx$offset,
        area = grid_cell_area_nmi2, bias_correct = FALSE,
        n_workers = 1, reference_label = "Compiled", verbose = FALSE), silent = TRUE)
      fitted <- !inherits(comp, "try-error") && !all(is.na(comp$sanity[[sv]]))
      ok <- fitted && isTRUE(comp$sanity[[sv]][rownames(comp$sanity) == "all_ok"])
      attempts[[step]] <- tibble::tibble(survey = sv, step = step, fitted = fitted, all_ok = ok,
                                         error = if (inherits(comp, "try-error")) conditionMessage(attr(comp, "condition")) else NA_character_)
      if (fitted && is.null(best)) best <- list(comp = comp, step = step)
      if (ok) {
        best <- list(comp = comp, step = step)
        break
      }
    }
    if (is.null(best)) best <- list(comp = comp, step = NA_character_)
    list(comp = best$comp, step = best$step, family = if (is.na(best$step)) NA_character_ else ladder[[best$step]]$family_name,
         dropped = dropped, attempts = dplyr::bind_rows(attempts))
  }
  future::plan(future::multicore, workers = n_workers)
  on.exit(future::plan(future::sequential), add = TRUE)
  res <- future.apply::future_lapply(surveys, one_survey, future.seed = TRUE)
  names(res) <- surveys
  comp <- merge_survey_comparisons(lapply(res, `[[`, "comp"), surveys)
  attr(comp, "steps") <- vapply(res, `[[`, character(1), "step")
  attr(comp, "families") <- vapply(res, `[[`, character(1), "family")
  attr(comp, "years_dropped") <- lapply(res, `[[`, "dropped")
  attr(comp, "attempts") <- dplyr::bind_rows(lapply(res, `[[`, "attempts"))
  attr(comp, "ladder") <- vapply(ladder, `[[`, character(1), "description")
  saveRDS(comp, report_cache(ctx, "surveys"))
  invisible(comp)
}

#' Simplification steps of the single-survey models
#'
#' @param ctx Report context.
#' @return A named list of steps, each with formula, family, fields and a description.
survey_model_ladder <- function(ctx) {
  form <- value ~ 0 + fyear + s(depth)
  as_component <- function(x) if (length(x) == 1L) x[[1]] else as.list(unlist(x))
  list(
    compiled = list(formula = form, family = ctx$family, family_name = ctx$final$FAMILY,
                    spatial = as_component(ctx$final$SPATIAL),
                    spatiotemporal = as_component(ctx$final$SPATIOTEMPORAL),
                    description = "the specification of the compiled model"),
    spatial_only = list(formula = form, family = ctx$family, family_name = ctx$final$FAMILY,
                        spatial = "on", spatiotemporal = "off",
                        description = "without the spatiotemporal field"),
    tweedie = list(formula = form, family = sdmTMB::tweedie(), family_name = "tweedie",
                   spatial = "on", spatiotemporal = "off",
                   description = "with the Tweedie family and without the spatiotemporal field")
  )
}

#' Combine single-survey comparisons into one `sdmTMB_survey_comparison` object
#'
#' @param comps Named list of `compare_surveys()` results, one survey each.
#' @param surveys Survey labels, in order.
#' @return An `sdmTMB_survey_comparison` object.
merge_survey_comparisons <- function(comps, surveys) {
  ok <- stats::setNames(!vapply(comps, inherits, logical(1), "try-error"), surveys)
  first <- comps[[which(ok)[1]]]
  ref <- attr(first, "reference_label")
  sanity <- do.call(cbind, lapply(surveys, function(sv) {
    x <- if (ok[[sv]]) comps[[sv]]$sanity[, sv, drop = FALSE]
    if (is.null(x)) x <- stats::setNames(data.frame(rep(NA, nrow(first$sanity)), row.names = rownames(first$sanity)), sv)
    x
  }))
  out <- list(
    sanity = sanity,
    settings = dplyr::bind_rows(lapply(comps[ok], `[[`, "settings")),
    index = dplyr::bind_rows(
      dplyr::filter(first$index, .data$model == ref, .data$domain == "full"),
      dplyr::bind_rows(lapply(comps[ok], function(x) dplyr::filter(x$index, !(.data$model == ref & .data$domain == "full"))))),
    grid = stats::setNames(lapply(surveys[ok], function(sv) comps[[sv]]$grid[[sv]]), surveys[ok])
  )
  class(out) <- "sdmTMB_survey_comparison"
  attr(out, "crs") <- attr(first, "crs")
  attr(out, "coord_multiplier") <- attr(first, "coord_multiplier")
  attr(out, "reference_label") <- ref
  attr(out, "surveys") <- surveys
  out
}

#' Leave-out refits with unused factor levels dropped
#'
#' Replaces `sdmTMBexperiments::sdmTMB_leave_out()` for the report. The package refit keeps
#' factor levels that vanish with the removed rows, so a year-factor model whose removed rows
#' carry the only records of a level becomes unidentifiable and the whole run stops. Here each
#' refit drops unused levels, reuses the mesh of the full model, and a failed refit is recorded
#' instead of stopping the others. The full-data index is the cached index of the product. The
#' result has the structure and class of `sdmTMB_leave_out()`.
#'
#' @param ctx Report context.
#' @param label Product label in `ctx$products`.
#' @param grid Report grid.
#' @param id_col Column identifying the units left out.
#' @param ids Units to leave out (all by default).
#' @param n_workers Parallel refits.
#' @return An `sdmTMB_leave_out` object.
report_leave_out <- function(ctx, label, grid, id_col, ids = NULL, n_workers = 7) {
  s <- ctx$products[[label]]
  fit <- readRDS(report_fit_file(ctx, s$file))
  if (isTRUE(attr(fit, "year_factor_failed"))) s <- report_no_year_spec(s, ctx)
  dat <- fit$data
  full <- readRDS(report_cache(ctx, paste0("post-", s$file)))$index
  ids <- unique(as.character(ids %||% dat[[id_col]]))
  data_years <- unique(dat$year)
  future::plan(future::multicore, workers = n_workers)
  on.exit(future::plan(future::sequential), add = TRUE)
  res <- future.apply::future_lapply(ids, function(k) {
    keep <- as.character(dat[[id_col]]) != k
    sk <- s
    sk$data <- drop_empty_levels(dat[keep, , drop = FALSE])
    removed_years <- setdiff(data_years, sk$data$year)
    out <- try({
      mesh <- sdmTMB::make_mesh(sk$data, xy_cols = c("X", "Y"), mesh = fit$spde$mesh)
      m <- fit_report_product(sk, ctx, mesh = mesh)
      g <- grid_for_fit(grid, m)
      for (v in intersect(names(g), names(m$data))) {
        if (is.factor(m$data[[v]]) && v != "fyear") g[[v]] <- factor(as.character(g[[v]]), levels = levels(m$data[[v]]))
      }
      idx <- predict_index(m, g, area = grid_cell_area_nmi2, bias_correct = FALSE)
      list(idx = idx, ok = report_passes(m))
    }, silent = TRUE)
    if (inherits(out, "try-error")) {
      message("Leave-out refit without ", k, " failed: ", conditionMessage(attr(out, "condition")))
      return(list(id = k, index = NULL, all_ok = NA))
    }
    idx <- as.data.frame(out$idx)
    idx$removed <- idx$year %in% removed_years
    list(id = k, index = dplyr::mutate(idx, id = k, .before = 1), all_ok = out$ok)
  }, future.seed = TRUE)
  index_out <- dplyr::bind_rows(lapply(res, `[[`, "index"))
  if (nrow(index_out) > 0) {
    index_out <- index_out |>
      dplyr::left_join(dplyr::select(full, "year", est_full = "est"), by = "year") |>
      dplyr::mutate(ratio = .data$est / .data$est_full) |>
      dplyr::select(-"est_full")
  }
  rows_by_year <- table(dat$year)
  id_info <- tibble::tibble(id = as.character(dat[[id_col]]), year = dat$year) |>
    dplyr::filter(.data$id %in% ids) |>
    dplyr::summarise(n_removed = dplyr::n(), id_years = list(sort(unique(.data$year))), .by = "id")
  id_info$haul_share <- id_info$n_removed /
    vapply(id_info$id_years, function(y) sum(rows_by_year[as.character(y)]), numeric(1))
  influence <- dplyr::left_join(
    id_info,
    tibble::tibble(id = vapply(res, `[[`, character(1), "id"),
                   all_ok = vapply(res, function(r) as.logical(r$all_ok), logical(1))),
    by = "id")
  stats_by_id <- if (nrow(index_out) > 0) {
    index_out |>
      dplyr::left_join(dplyr::select(id_info, "id", "id_years"), by = "id") |>
      dplyr::summarise(
        influence = {
          r <- .data$ratio[.data$year %in% .data$id_years[[1]] & !is.na(.data$ratio)]
          if (length(r) == 0) NA_real_ else 1 - exp(mean(log(r)))
        },
        max_abs_change = if (all(is.na(.data$ratio))) NA_real_ else max(abs(.data$ratio - 1), na.rm = TRUE),
        year_max_change = if (all(is.na(.data$ratio))) NA else .data$year[which.max(abs(.data$ratio - 1))],
        .by = "id")
  } else {
    tibble::tibble(id = character(), influence = numeric(), max_abs_change = numeric(),
                   year_max_change = integer())
  }
  influence <- dplyr::left_join(influence, stats_by_id, by = "id")
  influence$leverage <- influence$influence / influence$haul_share
  influence <- influence |>
    dplyr::relocate("leverage", .after = "influence") |>
    dplyr::relocate("all_ok", .after = dplyr::last_col()) |>
    dplyr::arrange(dplyr::desc(.data$influence))
  structure(list(full = full, index = index_out, influence = influence),
            class = "sdmTMB_leave_out", id_col = id_col, index_type = "plugin")
}

#' Leave-one-survey-out refits of the total biomass (IID) model
#'
#' @param ctx Report context.
#' @param grid Report grid.
#' @param n_workers Parallel refits.
#' @return An `sdmTMB_leave_out` object over the cruise series.
run_report_loso <- function(ctx, grid, n_workers = 7) {
  out <- report_leave_out(ctx, "Total biomass (IID)", grid, id_col = "cruiseseries", n_workers = n_workers)
  saveRDS(out, report_cache(ctx, "loso"))
  invisible(out)
}

#' Configured sensitivity refits
#'
#' `SENSITIVITIES` in config.yaml lists the refits, each with a `name` (cache
#' `sens-<name>.rds`), a `label` for the report and a `type`:
#'
#' * `drop`: refit `product` without the hauls that match every column of `filter`
#'   (e.g. `{cruiseseries: ["CoastalS"], samplequality: ["2"]}`);
#' * `keep`: refit `product` with only those hauls (e.g. the major survey series);
#' * `offset`: the other way of entering swept area. With a density report (`ctx$effort`):
#'   the response as catch with a log swept-area offset and the Poisson-link version of the
#'   selected delta family, so that tow length also enters the encounter probability. With an
#'   offset report (REPORT_EFFORT): the swept-area density without an offset, the response on
#'   which the model selection compared its candidates;
#' * `gear_width_door`: the swept area with the widths of `GEAR_WIDTHS_DOOR` (door-spread ratio,
#'   full herding by doors and sweeps) instead of `GEAR_WIDTHS`;
#' * `fishable_threshold`: the fishable product with another length threshold (`over_cm`,
#'   default `SENSITIVITY_OVER_CM`), the fishable share recomputed from the length data.
#'
#' `product` defaults to "Total biomass (IID)" (the fishable product for `fishable_threshold`).
#' Without `SENSITIVITIES`, the `offset` refit, the `gear_width_door` refit when
#' `GEAR_WIDTHS_DOOR` is set and the `fishable_threshold` refit when `SENSITIVITY_OVER_CM` is set
#' run. Only the trend of a refit is interpreted
#' (knowledge/index-level-and-trend.md).
#'
#' @param cfg Stock configuration.
#' @return A named list of sensitivity definitions.
report_sensitivities <- function(cfg) {
  x <- cfg$SENSITIVITIES
  if (is.null(x)) {
    offset_report <- identical(report_effort(cfg, cfg$FINAL_MODEL$FAMILY %||% cfg$FAMILY), "offset")
    x <- list(list(name = "offset", type = "offset",
                   label = if (offset_report) "Density response (as in the model selection)" else "Catch with swept-area offset"))
    if (length(cfg$GEAR_WIDTHS_DOOR))
      x <- c(x, list(list(name = "gear-width-door", type = "gear_width_door",
                          label = "Cod-trawl width from the door spread")))
    if (!is.null(cfg$SENSITIVITY_OVER_CM))
      x <- c(x, list(list(name = "fishable-threshold", type = "fishable_threshold",
                          label = paste0("Fishable threshold ", cfg$SENSITIVITY_OVER_CM, " cm"))))
  }
  stats::setNames(x, vapply(x, `[[`, "", "name"))
}

# Rows of `d` matching every column of `filter` (a list of column = allowed values).
match_filter <- function(d, filter) {
  hit <- rep(TRUE, nrow(d))
  for (col in names(filter)) {
    if (!col %in% names(d)) stop("Sensitivity filter column '", col, "' is not in the model data.")
    hit <- hit & as.character(d[[col]]) %in% as.character(unlist(filter[[col]]))
  }
  hit
}

#' Sensitivity refit of a report index
#'
#' Refits one product with the same specification and mesh after changing the data, the
#' response or the family (see `report_sensitivities()`), and compares its index with the
#' product's index.
#'
#' @param ctx Report context.
#' @param grid Report grid.
#' @param name Name of a configured sensitivity.
#' @return A list (cached as sens-<name>.rds) with the refit index, the product's index, the
#'   label, the product, the hauls (and positive hauls) removed, and the sanity result.
run_report_sensitivity <- function(ctx, grid, name) {
  def <- report_sensitivities(ctx$cfg)[[name]]
  if (is.null(def)) stop("No sensitivity '", name, "' in SENSITIVITIES.")
  type <- match.arg(def$type, c("drop", "keep", "offset", "gear_width_door", "fishable_threshold"))
  product <- def$product %||% if (type == "fishable_threshold") "Fishable biomass (IID)" else "Total biomass (IID)"
  s <- ctx$products[[product]]
  if (is.null(s)) stop("No product '", product, "' in the report.")
  fit <- readRDS(report_fit_file(ctx, s$file))
  if (isTRUE(attr(fit, "year_factor_failed"))) s <- report_no_year_spec(s, ctx)
  full <- readRDS(report_cache(ctx, paste0("post-", s$file)))$index
  d <- fit$data
  removed <- 0L
  removed_positive <- NA_integer_
  switch(type,
    drop = , keep = {
      hit <- match_filter(d, def$filter)
      out <- if (type == "drop") hit else !hit
      removed <- sum(out)
      removed_positive <- sum(out & d$value > 0)
      d <- d[!out, , drop = FALSE]
    },
    offset = if (identical(ctx$effort, "offset")) {
      # The report models catch with an offset: refit the density model of the selection.
      d$value <- if (grepl("fishable", s$file)) d$rho_biomass_fishable else d$rho_biomass
      s$offset <- FALSE
    } else {
      d$value <- if (grepl("fishable", s$file)) d$biomass_fishable else d$biomass
      d$log_swept_area <- log(d$swept_area)
      s$offset <- "log_swept_area"
      s$family <- switch(ctx$final$FAMILY,
        delta_lognormal = , delta_lognormal_poisson_link = sdmTMB::delta_lognormal(type = "poisson-link"),
        delta_gamma = , delta_gamma_poisson_link = sdmTMB::delta_gamma(type = "poisson-link"),
        stop("No Poisson-link version of ", ctx$final$FAMILY))
    },
    gear_width_door = {
      if (!length(ctx$cfg$GEAR_WIDTHS_DOOR)) stop("Set GEAR_WIDTHS_DOOR in config.yaml.")
      w_door <- gear_width_m(d$gearname, d$geartype, ctx$cfg, ctx$cfg$GEAR_WIDTHS_DOOR)
      if (identical(ctx$effort, "offset")) {
        d$log_swept_area <- log(swept_area_nmi2(d$distance, w_door))
      } else {
        d$value <- d$value * d$gear_width / w_door
      }
    },
    fishable_threshold = {
      over_cm <- as.numeric(def$over_cm %||% ctx$cfg$SENSITIVITY_OVER_CM)
      if (!length(over_cm)) stop("Set over_cm or SENSITIVITY_OVER_CM in config.yaml.")
      lengths <- readRDS(file.path(out_dir, "length-data.rds"))
      lw <- readRDS(file.path(out_dir, "compile-metadata.rds"))$lw
      all <- dplyr::select(ctx$dt, -dplyr::any_of(c("fishable_fraction", "fishable_imputed", "n_measured",
                                                    "biomass_fishable", "rho_biomass_fishable")))
      all <- add_fishable_biomass(all, lengths, lw, over_cm)
      all$value <- if (identical(ctx$effort, "offset")) all$biomass_fishable else all$rho_biomass_fishable
      pos_years <- unique(all$year[all$value > 0])
      d <- droplevels(all[all$year %in% pos_years, , drop = FALSE])
    })
  s$data <- drop_empty_levels(d)
  mesh <- sdmTMB::make_mesh(s$data, xy_cols = c("X", "Y"), mesh = fit$spde$mesh)
  m <- fit_report_product(s, ctx, mesh = mesh)
  g <- grid_for_fit(grid, m)
  for (v in intersect(names(g), names(m$data))) {
    if (is.factor(m$data[[v]]) && v != "fyear") g[[v]] <- factor(as.character(g[[v]]), levels = levels(m$data[[v]]))
  }
  out <- list(variant = name, label = def$label %||% name, product = product,
              index = predict_index(m, g, area = grid_cell_area_nmi2, bias_correct = FALSE),
              full = full, removed = removed, removed_positive = removed_positive,
              all_ok = report_passes(m), fit_minutes = attr(m, "fit_minutes"))
  saveRDS(out, report_cache(ctx, paste0("sens-", name)))
  invisible(out)
}

#' Level ratio and trend change of a sensitivity refit against the product's index
#'
#' @param sens Result of `run_report_sensitivity()`.
#' @return A one-row tibble: `level_ratio` (geometric mean ratio over the shared years),
#'   `trend_change` (geometric mean absolute deviation of the centred log ratios) and the year
#'   of the largest deviation.
sensitivity_change <- function(sens) {
  r <- dplyr::inner_join(dplyr::select(as.data.frame(sens$full), "year", full = "est"),
                         dplyr::select(as.data.frame(sens$index), "year", "est"), by = "year") |>
    dplyr::filter(is.finite(.data$est), .data$est > 0)
  lr <- log(r$est / r$full)
  dev <- lr - mean(lr)
  tibble::tibble(level_ratio = exp(mean(lr)), trend_change = exp(mean(abs(dev))) - 1,
                 year_max = r$year[which.max(abs(dev))])
}

#' Influence of individual cruises and hauls on the total biomass (IID) index
#'
#' Candidates are screened without refitting with `density_share()`: the cruises with the
#' largest share of a year's summed density relative to their share of the hauls (candidates
#' for a positive influence), the cruises with the smallest such ratio among those holding at
#' least 10 % of a year's hauls (candidates for a negative influence: many hauls with little
#' fish), and the hauls with the largest share of a year's summed density. Each candidate is
#' then left out in turn and the model refitted. Refits already in the cache are reused, so
#' adding candidates refits only the new ones.
#'
#' @param ctx Report context.
#' @param grid Report grid.
#' @param n_cruises,n_low_cruises,n_hauls Number of candidates refitted.
#' @param n_workers Parallel refits.
#' @return A list with the screens and the two leave-out results.
run_report_influence <- function(ctx, grid, n_cruises = 10, n_low_cruises = 5, n_hauls = 10, n_workers = 10) {
  fit <- readRDS(report_fit_file(ctx, "total-iid"))
  d <- fit$data
  # Density shares: catch per swept area with an offset report; the response is already a
  # density otherwise.
  d$unit_effort <- if (identical(ctx$effort, "offset")) d$swept_area else 1
  cruise_screen <- sdmTMBexperiments::density_share(d, value_col = "value", effort_col = "unit_effort",
                                                    group_col = "cruise_id") |>
    dplyr::mutate(ratio = .data$share / .data$haul_share)
  high_ids <- cruise_screen |>
    dplyr::filter(.data$share >= 0.1, .data$haul_share < 1) |>
    dplyr::arrange(dplyr::desc(.data$ratio)) |>
    dplyr::distinct(.data$cruise_id) |>
    utils::head(n_cruises) |>
    dplyr::pull(.data$cruise_id)
  low_ids <- cruise_screen |>
    dplyr::filter(.data$haul_share >= 0.1, .data$haul_share < 1, !.data$cruise_id %in% high_ids) |>
    dplyr::arrange(.data$ratio) |>
    dplyr::distinct(.data$cruise_id) |>
    utils::head(n_low_cruises) |>
    dplyr::pull(.data$cruise_id)
  haul_screen <- sdmTMBexperiments::density_share(d, value_col = "value", effort_col = "unit_effort")
  haul_ids <- haul_screen |>
    dplyr::arrange(dplyr::desc(.data$share)) |>
    utils::head(n_hauls) |>
    dplyr::pull(.data$haul_id)
  old <- read_report_cache(ctx, "influence")
  lo <- function(ids, col, previous) {
    ids <- as.character(ids)
    done <- if (!is.null(previous)) intersect(ids, previous$influence$id) else character()
    todo <- setdiff(ids, done)
    new <- if (length(todo)) report_leave_out(ctx, "Total biomass (IID)", grid, id_col = col, ids = todo, n_workers = n_workers)
    merge_leave_out(previous, new, ids)
  }
  out <- list(cruise_screen = cruise_screen, haul_screen = haul_screen,
              cruise = lo(c(high_ids, low_ids), "cruise_id", old$cruise),
              haul = lo(haul_ids, "haul_id", old$haul),
              low_cruises = low_ids)
  saveRDS(out, report_cache(ctx, "influence"))
  invisible(out)
}

#' Combine cached and new leave-out refits, keeping the units in `ids`
#'
#' @param a,b `sdmTMB_leave_out` objects (either may be NULL).
#' @param ids Units to keep.
#' @return An `sdmTMB_leave_out` object.
merge_leave_out <- function(a, b, ids) {
  parts <- purrr::compact(list(a, b))
  out <- parts[[1]]
  out$index <- dplyr::bind_rows(lapply(parts, `[[`, "index")) |> dplyr::filter(.data$id %in% ids)
  out$influence <- dplyr::bind_rows(lapply(parts, `[[`, "influence")) |>
    dplyr::filter(.data$id %in% ids) |>
    dplyr::distinct(.data$id, .keep_all = TRUE) |>
    dplyr::arrange(dplyr::desc(.data$influence))
  out
}

#' Mean absolute change of the index without each unit of a leave-out analysis
#'
#' @param lo An `sdmTMB_leave_out` object (with `ratio` in `index` and `id_years` in
#'   `influence`).
#' @return A tibble with `id` and `mean_abs_change`, the geometric mean absolute change
#'   `exp(mean(abs(log(ratio)))) - 1` over the years the unit has data.
leave_out_mean_change <- function(lo) {
  lo$index |>
    dplyr::left_join(dplyr::select(lo$influence, "id", "id_years"), by = "id") |>
    dplyr::filter(purrr::map2_lgl(.data$year, .data$id_years, ~ .x %in% .y),
                  !is.na(.data$ratio), .data$ratio > 0) |>
    dplyr::summarise(mean_abs_change = exp(mean(abs(log(.data$ratio)))) - 1, .by = "id")
}

#' Change in the trend of the index without each unit of a leave-out analysis
#'
#' A unit can move the level of the index without changing its trend, when it informs a
#' parameter shared by all years (for example the month effect at the reference month). The
#' trend change removes the level: the yearly log ratios are centred on their mean over all
#' years, so a pure level shift gives zero (knowledge/index-level-and-trend.md).
#'
#' @param lo An `sdmTMB_leave_out` object (with `ratio` in `index`).
#' @return A tibble with `id`, `level_ratio` (geometric mean ratio over all years) and
#'   `trend_change`, the geometric mean absolute deviation `exp(mean(abs(d))) - 1` of the
#'   centred log ratios `d`.
leave_out_trend_change <- function(lo) {
  lo$index |>
    dplyr::filter(!is.na(.data$ratio), .data$ratio > 0) |>
    dplyr::summarise(level_ratio = exp(mean(log(.data$ratio))),
                     trend_change = exp(mean(abs(log(.data$ratio) - mean(log(.data$ratio))))) - 1,
                     .by = "id")
}
