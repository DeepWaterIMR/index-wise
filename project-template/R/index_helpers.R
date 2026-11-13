# index_helpers.R — project-side helpers for effort, index years, prediction references, design
# balance and index checks. Sourced by R/0_setup.R after `cfg` is read. Generic sdmTMB helpers
# belong in sdmTMBexperiments; these encode this project template's conventions only.

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- Effort -----------------------------------------------------------------------------
# Swept area in nmi^2 from tow distance (nmi) and effective width (m). Write the unit conversion
# once and reuse it: a width in km multiplied by a km^2 -> nmi^2 factor looks plausible and is
# wrong by a constant, which no relative index will ever reveal.
swept_area_nmi2 <- function(distance_nmi, width_m) distance_nmi * width_m / 1852

# "density": response = catch / swept area, no offset (the Step 2 default).
# "offset":  response = catch, offset = log(swept area in nmi^2), prediction at offset 0.
effort_mode <- function(cfg) {
  mode <- cfg$EFFORT %||% "density"
  if (!mode %in% c("density", "offset"))
    stop("EFFORT in config.yaml must be \"density\" or \"offset\", not \"", mode, "\".")
  mode
}

# The offset as a column NAME. sdmTMB and sdmTMB_selection() accept a column name, which keeps
# the offset attached to its rows when a fit is updated on a subset (robustness refits).
# R/0_setup.R stores it as `model_offset`; pass that object, not a call, to sdmTMB().
offset_column <- function(cfg) {
  if (identical(effort_mode(cfg), "offset")) "log_swept_area" else NULL
}

# --- Index year -------------------------------------------------------------------------
# The index year an observation belongs to. With start_month = 1 it is the calendar year. With
# start_month = 7, a July-June season is labelled by the calendar year it starts ("start") or
# ends ("end"), so that, e.g., an autumn survey and the following winter survey share one step.
index_year <- function(year, month, start_month = 1L, label = "start") {
  start_month <- as.integer(start_month %||% 1L)
  if (!label %in% c("start", "end"))
    stop("INDEX_YEAR_LABEL must be \"start\" or \"end\", not \"", label, "\".")
  if (start_month == 1L) return(as.integer(year))
  if (anyNA(month[!is.na(year)]))
    stop("An index year not starting in January needs a month for every observation.")
  season_start <- ifelse(month >= start_month, year, year - 1L)
  as.integer(if (identical(label, "end")) season_start + 1L else season_start)
}

# The modelling frame shared by Steps 2-4: lon/lat, calendar and index year, month, the response
# implied by RESPONSE and EFFORT, the offset column, a survey factor and UTM coordinates (km).
prepare_model_data <- function(dt, cfg) {
  catch_col <- if (identical(cfg$RESPONSE, "abundance")) "count" else "biomass"
  density_col <- if (identical(cfg$RESPONSE, "abundance")) "rho_abundance" else "rho_biomass"
  value_col <- if (identical(effort_mode(cfg), "offset")) catch_col else density_col
  if (!value_col %in% names(dt)) stop("The compiled data have no `", value_col, "` column.")

  out <- dt |>
    dplyr::rename(lon = longitudestart, lat = latitudestart) |>
    dplyr::mutate(
      calendar_year = as.integer(startyear),
      month = as.integer(month),
      year = index_year(calendar_year, month, cfg$INDEX_YEAR_START_MONTH %||% 1L,
                        cfg$INDEX_YEAR_LABEL %||% "start"),
      value = .data[[value_col]]
    ) |>
    dplyr::filter(!is.na(value))

  if (identical(effort_mode(cfg), "offset")) {
    if (!"swept_area" %in% names(out) || any(!is.finite(out$swept_area) | out$swept_area <= 0))
      stop("EFFORT: offset needs a positive, finite `swept_area` (nmi^2) for every haul.")
    out$log_swept_area <- log(out$swept_area)
  }
  if ("cruiseseries" %in% names(out)) out$fsurvey <- factor(out$cruiseseries)
  sdmTMB::add_utm_columns(out, ll_names = c("lon", "lat"), utm_crs = cfg$CRS)
}

# --- Prediction region ------------------------------------------------------------------
# The stock prediction region that <stock>-3-data.qmd builds (PREDICTION_REGION_FILE, default
# data/source/<stock>-prediction-region.gpkg), in `crs`; NULL when the file does not exist.
read_prediction_region <- function(cfg, crs = cfg$CRS) {
  f <- cfg$PREDICTION_REGION_FILE %||%
    file.path(cfg$SOURCE_DIR %||% "data/source",
              paste0(cfg$STOCK_SLUG %||% cfg$SPECIES_SLUG, "-prediction-region.gpkg"))
  f <- here::here(f)
  if (!file.exists(f)) return(NULL)
  sf::st_transform(sf::read_sf(f), crs)
}

# Model data inside the prediction region (needs lon/lat from prepare_model_data()). The
# stations outside are zero hauls far from where the species occurs; they would only widen the
# mesh. Attribute "n_outside" counts them. With region = NULL the data are returned unchanged.
restrict_to_region <- function(dt, region) {
  if (is.null(region)) {
    attr(dt, "n_outside") <- 0L
    return(dt)
  }
  pts <- sf::st_as_sf(dt[, c("lon", "lat")], coords = c("lon", "lat"), crs = 4326) |>
    sf::st_transform(sf::st_crs(region))
  inside <- lengths(sf::st_intersects(pts, region)) > 0
  out <- dt[inside, , drop = FALSE]
  attr(out, "n_outside") <- sum(!inside)
  out
}

# Reference gear and month for the prediction grid: config values, else the most sampled level.
# They set the level of the index, not its trend. A hard-coded month outside the surveyed
# season extrapolates the month smooth.
reference_gear <- function(dt, cfg) cfg$REFERENCE_GEAR %||% names(which.max(table(dt$geartype)))
reference_month <- function(dt, cfg) {
  as.integer(cfg$REFERENCE_MONTH %||% names(which.max(table(dt$month))))
}

# Grid rows for the years a fit was given, with the year factor on that fit's levels (a fit can
# lack years, e.g. a fishable-length model without positive catches in a year).
grid_for_fit <- function(grid, fit) {
  g <- grid[grid[[fit$time]] %in% unique(fit$data[[fit$time]]), , drop = FALSE]
  if ("fyear" %in% names(fit$data)) g$fyear <- factor(g[[fit$time]], levels = levels(fit$data$fyear))
  g
}

# --- Prediction reference ---------------------------------------------------------------
# Reference levels for the survey factor and the catchability covariates. The index level
# depends on these, not its shape; every one must be a level with good coverage in the data.
add_reference_levels <- function(grid, dt, cfg) {
  if ("fsurvey" %in% names(dt)) {
    ref <- cfg$REFERENCE_SURVEY %||% names(which.max(table(dt$fsurvey)))
    if (!ref %in% levels(dt$fsurvey)) stop("REFERENCE_SURVEY '", ref, "' is not in the data.")
    grid$fsurvey <- factor(ref, levels = levels(dt$fsurvey))
  }
  refs <- cfg$CATCHABILITY_REFERENCE %||% list()
  for (v in unlist(cfg$CATCHABILITY_TERMS)) {
    if (!v %in% names(dt)) stop("Catchability term `", v, "` is not in the compiled data.")
    grid[[v]] <- refs[[v]] %||% stats::median(dt[[v]], na.rm = TRUE)
  }
  grid
}

# Grid cells outside the depth range the model was trained on. The depth smooth extrapolates
# there; report the share, and either trim the grid or justify keeping the cells.
depth_extrapolation <- function(grid, dt, depth_col = "depth") {
  rng <- range(dt[[depth_col]], na.rm = TRUE)
  d <- grid[[depth_col]]
  data.frame(
    observed_min = rng[1], observed_max = rng[2],
    cells = length(d),
    shallower = sum(d < rng[1], na.rm = TRUE),
    deeper = sum(d > rng[2], na.rm = TRUE),
    missing_depth = sum(is.na(d))
  )
}

# --- Prediction and index ---------------------------------------------------------------
# Predict on the grid years the model was fitted to, at offset 0 (one unit of swept area), and
# integrate with the grid cell area. Predictions are then densities in the response's area unit
# whatever the effort mode, and `area` scales them exactly once.
predict_index <- function(fit, newdata, area, bias_correct = FALSE, ...) {
  years <- sort(unique(fit$data[[fit$time]]))
  newdata <- newdata[newdata[[fit$time]] %in% years, , drop = FALSE]
  zero <- rep(0, nrow(newdata))
  # sdmTMB >= 1.2.0 takes the fit and newdata directly (return_tmb_object is deprecated there).
  if ("newdata" %in% names(formals(sdmTMB::get_index))) {
    return(sdmTMB::get_index(fit, newdata = newdata, offset = zero, area = area,
                             bias_correct = bias_correct, ...))
  }
  pred <- predict(fit, newdata = newdata, return_tmb_object = TRUE, offset = zero)
  sdmTMB::get_index(pred, area = area, bias_correct = bias_correct, ...)
}

# Two checks of the absolute index scale.
# (1) Units, independent of coverage: the model's density at the sampled hauls (prediction at
#     offset 0) against the observed density there. A wrong swept-area unit in the offset, or an
#     offset on the wrong scale, moves this ratio by the size of the error; `ok` is based on it.
#     It needs `fit` and the density column in `fit$data`.
# (2) Design comparison: the model index against an unstratified swept-area estimate (mean
#     observed density per year times the grid area). The two legitimately differ when coverage
#     is uneven (the grid includes cells the survey rarely samples), so read this ratio as
#     context, not as a pass/fail: only a large departure (e.g. > 10x) suggests a cell area or a
#     tow-distance division in the wrong place.
check_index_scale <- function(index, dt, total_area, density_col = "rho_biomass",
                              time_col = "year", fit = NULL, tolerance = 1.5) {
  design <- dt |>
    dplyr::group_by(.data[[time_col]]) |>
    dplyr::summarise(mean_density = mean(.data[[density_col]], na.rm = TRUE),
                     hauls = dplyr::n(), .groups = "drop") |>
    dplyr::mutate(design_est = mean_density * total_area)
  out <- dplyr::inner_join(index[, c(time_col, "est")], design, by = time_col) |>
    dplyr::mutate(design_ratio = est / design_est)
  design_med <- stats::median(out$design_ratio[is.finite(out$design_ratio)])

  unit_med <- NA_real_
  if (!is.null(fit)) {
    obs <- fit$data
    if (!density_col %in% names(obs)) stop("`fit$data` has no `", density_col, "` column.")
    obs$fitted_density <- predict(fit, newdata = obs, type = "response",
                                  offset = rep(0, nrow(obs)))$est
    units <- obs |>
      dplyr::group_by(.data[[time_col]]) |>
      dplyr::summarise(unit_ratio = mean(fitted_density) / mean(.data[[density_col]]),
                       .groups = "drop")
    out <- dplyr::left_join(out, units, by = time_col)
    unit_med <- stats::median(out$unit_ratio[is.finite(out$unit_ratio)])
  }
  list(table = out, unit_ratio = unit_med, design_ratio = design_med,
       ok = if (is.null(fit)) NA else
         is.finite(unit_med) && unit_med >= 1 / tolerance && unit_med <= tolerance)
}

# --- Design balance ---------------------------------------------------------------------
# Hauls per year and level of a design factor (survey, gear, vessel, nation). A level whose
# share swings between years is confounded with the year effect: its catchability difference
# is estimated from few years and can be read as a trend.
design_balance <- function(dt, factor_col, time_col = "year", shift_threshold = 0.5) {
  counts <- dt |>
    dplyr::count(.data[[time_col]], .data[[factor_col]], name = "hauls") |>
    dplyr::group_by(.data[[time_col]]) |>
    dplyr::mutate(share = hauls / sum(hauls)) |>
    dplyr::ungroup()
  years <- sort(unique(dt[[time_col]]))
  shift <- counts |>
    dplyr::group_by(.data[[factor_col]]) |>
    dplyr::summarise(
      years_present = dplyr::n(),
      min_share = if (dplyr::n() < length(years)) 0 else min(share),
      max_share = max(share),
      .groups = "drop"
    ) |>
    dplyr::mutate(share_range = max_share - min_share,
                  flagged = share_range > shift_threshold)
  wide <- as.data.frame.matrix(stats::xtabs(
    stats::as.formula(paste("hauls ~", time_col, "+", factor_col)), data = counts))
  list(counts = counts, wide = wide, shift = shift)
}

# Positive hauls without individual (length) data, per year. Such hauls stay in the total
# product and are never zero in size-, sex- or length-specific products: their shares are imputed
# and flagged (add_fishable_biomass()) or they are dropped there. `measured_col` counts the
# measured target individuals per haul (0 when none).
length_coverage <- function(dt, measured_col = "n_measured", catch_col = "biomass",
                            time_col = "year") {
  if (!measured_col %in% names(dt))
    stop("Add `", measured_col, "` (measured target individuals per haul) in Step 1.")
  dt |>
    dplyr::filter(.data[[catch_col]] > 0) |>
    dplyr::group_by(.data[[time_col]]) |>
    dplyr::summarise(
      positive_hauls = dplyr::n(),
      without_lengths = sum(.data[[measured_col]] %in% 0 | is.na(.data[[measured_col]])),
      catch_without_lengths = sum(.data[[catch_col]][.data[[measured_col]] %in% 0 |
                                                     is.na(.data[[measured_col]])]),
      catch_total = sum(.data[[catch_col]]),
      .groups = "drop"
    ) |>
    dplyr::mutate(share_hauls = without_lengths / positive_hauls,
                  share_catch = catch_without_lengths / catch_total)
}

# --- Bridging ---------------------------------------------------------------------------
# Compare the new index with the previous assessment's published index on the overlapping
# years. Both are rescaled to their mean over the overlap, so only the shape is compared.
compare_with_previous <- function(index, previous, tolerance = 0.2, time_col = "year") {
  if (!all(c(time_col, "est") %in% names(previous)))
    stop("The previous index needs `", time_col, "` and `est` columns.")
  both <- dplyr::inner_join(
    index[, c(time_col, "est")],
    dplyr::rename(previous[, c(time_col, "est")], est_previous = est),
    by = time_col
  )
  if (nrow(both) < 2) stop("Fewer than two overlapping years with the previous index.")
  both <- both |>
    dplyr::mutate(
      new = est / mean(est),
      previous = est_previous / mean(est_previous),
      rel_change = new / previous - 1,
      flagged = abs(rel_change) > tolerance
    )
  last <- both[[time_col]] == max(both[[time_col]])
  list(table = both,
       median_abs_change = stats::median(abs(both$rel_change)),
       terminal_change = both$rel_change[last],
       flagged_years = both[[time_col]][both$flagged])
}

# --- Robustness -------------------------------------------------------------------------
# Subsample whole STATIONS within each year. Sampling rows instead drops parts of a station
# (e.g. some size classes of a stacked class model) and changes the data structure.
subsample_stations <- function(dt, prop, seed = 1, station_col = "haul_id", time_col = "year") {
  set.seed(seed)
  keep <- dt |>
    dplyr::distinct(.data[[time_col]], .data[[station_col]]) |>
    dplyr::group_by(.data[[time_col]]) |>
    dplyr::slice_sample(prop = prop) |>
    dplyr::ungroup()
  dplyr::semi_join(dt, keep, by = c(time_col, station_col))
}

# Refit a model to new data with a fresh mesh at the same cutoff. Gaps in the remaining years are
# passed as extra_time when the spatiotemporal field needs evenly spaced steps (ar1/rw), as in
# the main fit. A year fixed effect must then be a precomputed factor column (`fyear`), never
# factor(year) in the formula: the extra levels make the model non-identifiable (sdmTMB #320).
# Barrier meshes are not rebuilt here; add the barrier again if the selected model uses one.
refit_on <- function(fit, data, cutoff, ...) {
  mesh <- sdmTMB::make_mesh(data, xy_cols = c("X", "Y"), cutoff = cutoff)
  years <- sort(unique(data[[fit$time]]))
  gaps <- setdiff(seq(min(years), max(years)), years)
  needs_steps <- any(fit$spatiotemporal %in% c("ar1", "rw"))
  args <- c(list(fit, data = data, mesh = mesh),
            if (needs_steps && length(gaps)) list(extra_time = gaps), list(...))
  do.call(stats::update, args)
}
