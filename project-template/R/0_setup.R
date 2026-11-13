# 0_setup.R — shared setup sourced by every document in this project.
# Loads packages, reads config.yaml into `cfg`, sets a ggplot theme, and derives a few
# convenience values. Keep project-wide settings in config.yaml, not here.

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- Packages ---------------------------------------------------------------------------
# The shared helper is copied from wise-writing during scaffolding, so projects remain
# self-contained after they leave this pack.
.setup_frames <- sys.frames()
.setup_file <- if (length(.setup_frames)) .setup_frames[[length(.setup_frames)]]$ofile else NULL
.setup_root <- if (!is.null(.setup_file) && nzchar(.setup_file)) {
  dirname(dirname(normalizePath(.setup_file, mustWork = FALSE)))
} else {
  getwd()
}
source(file.path(.setup_root, "R", "package_setup.R"))
rm(.setup_frames, .setup_file, .setup_root)

# Every package this project uses, named ONCE, with the GitHub repository for those that are
# not on CRAN and NA for the rest. `sdmTMBexperiments` must be ATTACHED (not used as `::`) so
# that ggOceanMaps land data is on the search path. Missing packages are not installed unless
# the analyst explicitly opts in for a run with R_INDEX_INSTALL_MISSING=true. The shared helper
# also respects renv and R_AW_INSTALL_MISSING=false.
#
# `here` and `knitr` are deliberately absent: each qmd calls `here::here()` in its own setup
# chunk *before* sourcing this file, so both must already exist for that source() to run at all.
# Quarto brings knitr, and here is a dependency of nearly everything else.
#
# If the project uses renv (there is an renv.lock), let renv::restore() own the library.
packages <- c(
  tidyverse = NA,
  sf = NA,
  scales = NA,
  cowplot = NA,
  ggspatial = NA,
  ggnewscale = NA,
  DBI = NA,        # Biotic database access for the Step 1 compile documents
  duckdb = NA,
  jsonlite = NA,
  yaml = NA,
  ggOceanMaps = "MikkoVihtakari/ggOceanMaps",
  sdmTMB = "sdmTMB/sdmTMB",   # org renamed from pbs-assess; the old path still redirects
  sdmTMBexperiments = "DeepWaterIMR/sdmTMBexperiments",
  ggFishPlots = "DeepWaterIMR/ggFishPlots"   # length-weight fit (>= 0.4.11 for outlier.sd)
)

# Needed only on some paths, so not installed until something asks for them:
#   sdmTMBextra  BARRIER: true (barrier mesh)
#   blockCV      the spatial block cross-validation in validate.qmd
#   RstoxUtils   reading SPD files in <stock>-2-survey-selection.qmd
#   suncalc      sun altitude as a catchability covariate (CATCHABILITY_TERMS: sun_altitude)
#   glmmTMB      CPUE GLMMs in cpue.qmd (CPUE: engine: glmmTMB); mgcv ships with R
#   DHARMa       grouped residual dispersion in cpue.qmd
#   future       parallel backends, if a document sets one up
# Call ensure_packages("blockCV") in the chunk that needs one.
optional_packages <- c(
  sdmTMBextra = "pbs-assess/sdmTMBextra",
  blockCV = NA,
  RstoxUtils = "DeepWaterIMR/RstoxUtils",
  suncalc = NA,
  glmmTMB = NA,
  DHARMa = NA,
  future = NA,
  plotly = NA      # interactive survey-timing figure (static fallback without it)
)

# Set R_INDEX_INSTALL_MISSING=true only after package installation has been authorized.
install_missing_packages <- identical(
  tolower(trimws(Sys.getenv("R_INDEX_INSTALL_MISSING", unset = "false"))), "true")

install_packages_if_missing <- function(pkgs) {
  package_setup(pkgs, install_missing_packages = install_missing_packages,
                project_root = getwd(), attach = function(packages) invisible(NULL))
}

# Install-and-attach an optional package at the point of use, e.g. ensure_packages("blockCV").
ensure_packages <- function(...) {
  nms <- c(...)
  known <- c(packages, optional_packages)
  unknown <- setdiff(nms, names(known))
  if (length(unknown))
    stop("Not listed in `packages` or `optional_packages` in R/0_setup.R: ",
         paste(unknown, collapse = ", "))
  package_setup(known[nms], install_missing_packages = install_missing_packages,
                project_root = getwd())
}

package_setup(packages, install_missing_packages = install_missing_packages,
              project_root = getwd())
# Data access (Biotic database) is provided by BAIT — see its biotic-connect skill.

# --- Config -----------------------------------------------------------------------------
# Documents may be rendered with the working directory at the project root (recommended) or
# at the qmd's own folder; find config.yaml either way.
.find_config <- function() {
  for (p in c("config.yaml", "../config.yaml", "../../config.yaml", "../../../config.yaml", "../../../../config.yaml"))
    if (file.exists(p)) return(normalizePath(p))
  stop("config.yaml not found. Render from the project root, or set the working directory.")
}
# Read as UTF-8 bytes so Norwegian species names (å/æ/ø) parse regardless of R locale.
.read_yaml_utf8 <- function(path) {
  txt <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  yaml::yaml.load(txt, eval.expr = FALSE)
}
cfg <- .read_yaml_utf8(.find_config())

# yaml parses an unquoted whole number as an R integer, and an integer `cutoff` makes
# sdmTMB::make_mesh() build one vertex per unique location (53 221 instead of 76 vertices for
# one 14 683-haul dataset) with only a generic ">1000 vertices" warning. Coerce every
# measurement-like setting to double here, once. CRS codes and row/year counts stay integer:
# they are identifiers, and a row limit must not become 2.5e+05 in a SQL LIMIT. Add any new
# numeric measurement setting to this list.
for (.nm in c("OVER_CM", "GEAR_WIDTH", "GRID_KM", "MESH_CUTOFF_KM", "MAX_DEPTH",
              "REFERENCE_MONTH")) {
  if (is.integer(cfg[[.nm]])) cfg[[.nm]] <- as.numeric(cfg[[.nm]])
}
rm(.nm)

# Effort, index-year, prediction-reference, balance, bridging and robustness helpers.
source(here::here("R", "index_helpers.R"))
# Commercial CPUE helpers (docs/sdmtmb/cpue).
source(here::here("R", "cpue_helpers.R"))

# Derived convenience values.
dt_crs         <- cfg$CRS
grid_side_size <- cfg$GRID_KM                       # km
grid_cell_area_nmi2 <- (cfg$GRID_KM / 1.852)^2      # nmi^2 per cell (for get_index area=)

# RESPONSE names the biological quantity; EFFORT names how sampled area enters the model.
# "density" models swept-area density (rho_*) with no offset; "offset" models raw catch with
# log(swept_area) as an offset, which the prepare chunks add as the `log_swept_area` column.
# Pass the offset to sdmTMB() and sdmTMB_cv() as that column NAME, never as a vector (the CV
# folds must subset it) and never as an explicit NULL (sdmTMB_cv() rejects it): use
# `offset = model_offset` in sdmTMB(), and `args$offset <- model_offset` in argument lists.
effort_model <- effort_mode(cfg)   # validates EFFORT (R/index_helpers.R)
model_quantity <- if (identical(cfg$RESPONSE, "abundance")) "abundance" else "biomass"
response_col <- if (identical(effort_model, "offset")) {
  if (identical(model_quantity, "abundance")) "count" else "biomass"
} else {
  paste0("rho_", model_quantity)
}
model_offset <- offset_column(cfg)

# Poisson-link delta families use the `type = "poisson-link"` argument (the
# delta_poisson_link_*() constructors are deprecated). Their first link is "log", not "logit":
# the first linear predictor is log group density, and the offset enters both components.
model_family <- switch(cfg$FAMILY,
  delta_lognormal              = sdmTMB::delta_lognormal(),
  delta_gamma                  = sdmTMB::delta_gamma(),
  delta_lognormal_poisson_link = sdmTMB::delta_lognormal(type = "poisson-link"),
  delta_gamma_poisson_link     = sdmTMB::delta_gamma(type = "poisson-link"),
  tweedie                      = sdmTMB::tweedie(),
  stop("Unknown FAMILY in config.yaml: ", cfg$FAMILY)
)

# sdmTMB() takes `spatial` as one value for a one-part family and as a list with one entry per
# component for a delta family. config.yaml stores SPATIAL as a value or a sequence.
model_spatial <- local({
  s <- cfg$SPATIAL %||% "on"
  if (length(s) == 1L) s[[1]] else as.list(unlist(s))
})

# Log density per prediction row from a delta model, which predict() returns as est1/est2.
# A logit first link gives log(plogis(est1)) + est2; a Poisson-link first link is already log
# group density, so the sum is est1 + est2. plogis() on a Poisson-link est1 gives a
# plausible-looking but meaningless map.
delta_log_density <- function(pred, fit) {
  if (identical(fit$family$link[1], "log")) pred$est1 + pred$est2
  else stats::plogis(pred$est1, log.p = TRUE) + pred$est2
}

# Random fields present in a fit, so diagnostics plot only those (plot_random_field() errors on
# a field that was switched off rather than skipping it).
fitted_fields <- function(fit) {
  c(if (any(unlist(fit$spatial) == "on")) "omega",
    if (any(fit$spatiotemporal != "off")) "epsilon")
}

# A smooth term sized to the data it will be given. mgcv needs at least `k` unique covariate
# values for `s(x, k = k)`; with fewer, sdmTMB stops with "A term has fewer unique covariate
# combinations than specified maximum degrees of freedom" — an opaque way of saying "this
# survey only sampled three months". Falls back to a smaller basis, then to a linear term, then
# to dropping the term altogether when the covariate is constant. Pass `data` and the formula
# adapts; omit it and you get the plain `s(var)` default.
smooth_term <- function(var, data = NULL, k = 10) {
  if (is.null(data) || !var %in% names(data)) return(paste0("s(", var, ")"))
  n <- dplyr::n_distinct(data[[var]][!is.na(data[[var]])])
  if (n < 2) return(NULL)           # constant: nothing to estimate
  if (n < 4) return(var)            # too few knots for a smooth; keep it linear
  if (n <= k) return(paste0("s(", var, ", k = ", n - 1L, ")"))
  paste0("s(", var, ")")
}

# The fixed-effect terms this project's config implies, sized to `data` when it is given.
# geartype stays in when there is >1 major gear type OR a single set gear width is used (so the
# model absorbs the gear-width difference). Temperature is off by default (INCLUDE_TEMPERATURE).
# SURVEY_EFFECT adds a cruise-series catchability factor (`fsurvey`); CATCHABILITY_TERMS adds a
# smooth per catchability covariate (e.g. hour, sun_altitude), predicted at a reference value.
model_terms <- function(cfg, has_multiple_gears = TRUE, data = NULL) {
  several_surveys <- is.null(data) || !"fsurvey" %in% names(data) ||
    dplyr::n_distinct(data$fsurvey) > 1
  c(
    if (has_multiple_gears || !identical(cfg$GEAR_WIDTH, "per_gear")) "geartype",
    if (isTRUE(cfg$SURVEY_EFFECT) && several_surveys) "fsurvey",
    # A month smooth with very uneven seasonal coverage can collapse (SD at 0, NaN SEs on every
    # fixed effect, NaN index limits); INCLUDE_MONTH: false drops it.
    if (isTRUE(cfg$INCLUDE_MONTH %||% TRUE)) smooth_term("month", data),
    smooth_term("depth", data),
    if (isTRUE(cfg$INCLUDE_TEMPERATURE)) smooth_term("temperature", data),
    unlist(lapply(unlist(cfg$CATCHABILITY_TERMS), smooth_term, data = data))
  )
}

# Default model formula.
build_formula <- function(cfg, has_multiple_gears = TRUE, data = NULL) {
  stats::as.formula(
    paste("value ~ 0 +", paste(model_terms(cfg, has_multiple_gears, data), collapse = " + "))
  )
}

# --- Model-selection helpers ------------------------------------------------------------
# Drop-one candidates from a full term set, for the fixed-effect selection stage. Returns a
# named list of formulas: the full model, one model per term removed, and the null model.
drop_one_candidates <- function(terms, response = "value") {
  full <- stats::as.formula(paste(response, "~ 0 +", paste(terms, collapse = " + ")))
  out <- c(
    list("Full model" = full),
    stats::setNames(
      lapply(terms, function(x) {
        rest <- setdiff(terms, x)
        if (!length(rest)) return(stats::as.formula(paste(response, "~ 1")))
        stats::as.formula(paste(response, "~ 0 +", paste(rest, collapse = " + ")))
      }),
      # "s(month, k = 4)" -> "No month": name the row after the variable, not the basis.
      paste("No", gsub("^s\\(([^,)]*).*$", "\\1", terms))
    ),
    list("Null model" = stats::as.formula(paste(response, "~ 1")))
  )
  out
}

# Print an sdmTMBexperiments selection table. Keeps the columns that carry the argument --
# what was fitted, whether it is comparable, and by how much it differs -- and drops the rest.
selection_kable <- function(sel, caption = NULL) {
  tab <- if (inherits(sel, "sdmTMB_selection")) sel$table else sel
  cv  <- "cv_loglik" %in% names(tab)

  out <- tab |>
    dplyr::transmute(
      Model = .data$model,
      Formula = .data$formula,
      Family = .data$family,
      ST = .data$spatiotemporal,
      n = .data$n,
      Converged = .data$converged,
      Sanity = .data$sanity,
      Comparable = .data$comparable,
      AIC = round(.data$AIC),
      `ΔAIC` = round(.data$deltaAIC, 1),
      w = round(.data$AICweight, 3)
    )

  if (cv) {
    out <- dplyr::bind_cols(out, tab |> dplyr::transmute(
      Folds = paste0(.data$folds_pdhess, "/", .data$folds),
      `Held out` = .data$n_heldout,
      `logLik/obs` = round(.data$cv_loglik, 4),
      `ΔNLL` = round(.data$cv_deltaNLL, 4),
      RMSE = signif(.data$cv_RMSE, 3),
      MAE = signif(.data$cv_MAE, 3)
    ))
  }

  knitr::kable(out, caption = caption)
}

# --- Paths ------------------------------------------------------------------------------
out_dir <- here::here(cfg$OUTPUT_DIR %||% "data/output")
src_dir <- here::here(cfg$SOURCE_DIR %||% "data/source")
figures_dir <- here::here(cfg$FIGURES_DIR %||% "figures")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# --- Theme ------------------------------------------------------------------------------
theme_set(theme_bw(base_size = cfg$BASE_SIZE %||% 12))
