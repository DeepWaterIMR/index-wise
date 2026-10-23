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
  sdmTMBexperiments = "DeepWaterIMR/sdmTMBexperiments"
)

# Needed only on some paths, so not installed until something asks for them:
#   sdmTMBextra  BARRIER: true (barrier mesh)
#   blockCV      the spatial block cross-validation in validate.qmd
#   ggFishPlots  the length-weight figure in the data report
#   RstoxUtils   reading SPD files in compile-data.qmd
#   future       parallel backends, if a document sets one up
# Call ensure_packages("blockCV") in the chunk that needs one.
optional_packages <- c(
  sdmTMBextra = "pbs-assess/sdmTMBextra",
  blockCV = NA,
  ggFishPlots = "DeepWaterIMR/ggFishPlots",
  RstoxUtils = "DeepWaterIMR/RstoxUtils",
  future = NA
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
  for (p in c("config.yaml", "../config.yaml", "../../config.yaml", "../../../config.yaml"))
    if (file.exists(p)) return(normalizePath(p))
  stop("config.yaml not found. Render from the project root, or set the working directory.")
}
# Read as UTF-8 bytes so Norwegian species names (å/æ/ø) parse regardless of R locale.
.read_yaml_utf8 <- function(path) {
  txt <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  yaml::yaml.load(txt)
}
cfg <- .read_yaml_utf8(.find_config())

# Derived convenience values.
dt_crs         <- cfg$CRS
grid_side_size <- cfg$GRID_KM                       # km
grid_cell_area_nmi2 <- (cfg$GRID_KM / 1.852)^2      # nmi^2 per cell (for get_index area=)
response_col   <- if (identical(cfg$RESPONSE, "abundance")) "rho_abundance" else "rho_biomass"

model_family <- switch(cfg$FAMILY,
  delta_lognormal = sdmTMB::delta_lognormal(),
  delta_gamma     = sdmTMB::delta_gamma(),
  tweedie         = sdmTMB::tweedie(),
  stop("Unknown FAMILY in config.yaml: ", cfg$FAMILY)
)

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
model_terms <- function(cfg, has_multiple_gears = TRUE, data = NULL) {
  c(
    if (has_multiple_gears || !identical(cfg$GEAR_WIDTH, "per_gear")) "geartype",
    smooth_term("month", data),
    smooth_term("depth", data),
    if (isTRUE(cfg$INCLUDE_TEMPERATURE)) smooth_term("temperature", data)
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
