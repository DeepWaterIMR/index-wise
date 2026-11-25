# Model-selection stages run as separate server processes, one per candidate, so that a crash
# loses one candidate and a rerun resumes from the cache. Each stage has two phases: every
# candidate is fitted to the full data (AIC, sanity, index), then a shortlist is
# cross-validated with the saved space-time block folds. `assemble_stage()` combines the cached
# results, applies the stage's decision rule and writes `stage-<stage>.rds`, which the next
# stage and the validate document read. Decisions so far live in `decisions.rds`.
#
#   Rscript R/validation/run_candidate.R <species> <stage> <candidate> <fit|cv> [n_workers]
#   Rscript R/validation/assemble_stage.R <species> <stage> <fit|final>
#   R/validation/run_species.sh <species>      # drives all stages with retries
#
# <species> is the stock key (SPECIES_SETTINGS key, or STOCK_SLUG of a single-stock project).
# Settings come from the SELECTION block of config.yaml (defaults in selection_settings()); the
# method is index-wise knowledge/model-selection.md.

# SELECTION settings with their defaults.
selection_settings <- function(cfg) {
  x <- cfg$SELECTION %||% list()
  list(
    cv_top_n = as.integer(x$CV_TOP_N %||% 3L),           # AIC shortlist size for CV
    mesh_tol = as.numeric(x$MESH_TOL %||% 0.05),         # mesh index tolerance
    grid_tol = as.numeric(x$GRID_TOL %||% 0.01),         # grid index tolerance
    window = as.integer(x$WINDOW %||% 5L),               # years in the end-of-series mean
    grid_ladder = as.numeric(unlist(x$GRID_LADDER_KM %||% c(5, 10, 20, 30, 50, 100, 200))),
    # Restrict the field decision to IID fields with a year factor (an index for a state-space
    # assessment model such as SPiCT; knowledge/model-selection.md, The assessment constraint).
    iid_year_only = isTRUE(x$IID_YEAR_ONLY %||% TRUE),
    # Extra fixed-effect candidates: month as a smooth (when the month is a factor), a
    # cruise-series factor, a trawl-model group in place of the gear type, quadratic depth.
    fixed_extra = unlist(x$FIXED_EXTRA %||% c("month_smooth", "fsurvey", "fgear", "quadratic_depth"))
  )
}

stage_setup <- function(species) {
  index_species <<- species
  source(here::here("R", "0_setup.R"), local = globalenv())
  source(here::here("R", "report_helpers.R"), local = globalenv())
  suppressPackageStartupMessages(library(sdmTMBexperiments))
  dt <- load_model_data(cfg, out_dir, dt_crs)
  sel_dir <- file.path(out_dir, "selection")
  dir.create(sel_dir, recursive = TRUE, showWarnings = FALSE)
  terms <- model_terms(cfg, has_multiple_gears = dplyr::n_distinct(dt$geartype) > 1, data = dt)
  grid <- readRDS(file.path(out_dir, "prediction-grid.rds"))
  grid$fyear <- factor(grid$year, levels = levels(dt$fyear))
  folds <- load_cv_folds(dt, cfg, out_dir, sel_dir)
  # Smoke test: SMOKE=1 fits a small subset with a coarse mesh into a temporary cache.
  if (nzchar(Sys.getenv("SMOKE"))) {
    set.seed(1)
    keep <- sort(sample(nrow(dt), 2500))
    dt <- droplevels(dt[keep, ]); dt$fyear <- factor(dt$year)
    folds <- folds[keep]
    sel_dir <- file.path(tempdir(), "smoke")
    dir.create(sel_dir, showWarnings = FALSE)
    grid <- grid[grid$year %in% dt$year, ]
    grid$fyear <- factor(grid$year, levels = levels(dt$fyear))
  }
  list(cfg = cfg, set = selection_settings(cfg), dt = dt, sel_dir = sel_dir, terms = terms, grid = grid, folds = folds,
       extra_time = setdiff(seq(min(dt$year), max(dt$year)), unique(dt$year)))
}

# The specification carried between stages. Stage 1 (mesh) writes the first decisions.rds
# (assemble_mesh()); without it the base specification uses the config mesh.
read_decisions <- function(s) {
  f <- file.path(s$sel_dir, "decisions.rds")
  if (file.exists(f)) return(readRDS(f))
  # MESH_ASSUMED_KM: stages 2-5 run alongside the mesh stage with this mesh (the driver checks
  # the mesh decision afterwards and flags a rerun if it differs).
  assumed <- as.numeric(Sys.getenv("MESH_ASSUMED_KM", "NA"))
  list(mesh_km = if (nzchar(Sys.getenv("SMOKE"))) 150 else if (!is.na(assumed)) assumed else as.numeric(s$cfg$MESH_CUTOFF_KM),
       terms = s$terms, positive_terms = NULL, year = TRUE,
       spatial = "on", spatiotemporal = "iid", anisotropy = FALSE, barrier = FALSE,
       family = s$cfg$FAMILY)
}

mesh_ladder <- function(cfg) paste(as.numeric(unlist(cfg$MESH_LADDER_KM %||% c(15, 20, 30, 40, 50))), "km")

# Stage 1 decision, as stated in the validate document: the reference is the best cutoff by
# ELPD among those that pass every sanity() check; the selected cutoff is the coarsest (fastest)
# one that passes sanity() and whose index is within `tol` of the reference index (terminal
# year, mean of the last `window` years, MARD; level included), with every cutoff between it
# and the reference within `tol` too. Writes the base specification with this mesh to
# decisions.rds.
assemble_mesh <- function(species, tol = NULL, window = NULL) {
  s <- stage_setup(species)
  tol <- tol %||% s$set$mesh_tol
  window <- window %||% s$set$window
  nm <- mesh_ladder(s$cfg)
  st <- read_stage(s, "mesh", nm, with_cv = TRUE)
  cvp <- cv_paired(list(cv = st$cv), group = cv_groups(s$dt, attr(s$folds, "block_km")))
  sane <- st$table$model[st$table$converged & st$table$pdHess & st$table$sanity]
  ref <- with(cvp[cvp$model %in% sane, ], model[which.max(elpd)])
  idx <- dplyr::bind_rows(lapply(nm, function(m) if (!is.null(st$index[[m]])) dplyr::mutate(st$index[[m]], model = m)))
  last <- max(idx$year)
  stab <- idx |>
    dplyr::inner_join(dplyr::filter(idx, model == ref) |> dplyr::select(year, ref_est = est), by = "year") |>
    dplyr::mutate(r = est / ref_est - 1) |>
    dplyr::group_by(model) |>
    dplyr::summarise(terminal = r[year == last], rho = mean(r[year > last - window]),
                     mard = mean(abs(r)), .groups = "drop") |>
    dplyr::mutate(km = as.numeric(sub(" km", "", model)),
                  stable = abs(terminal) <= tol & abs(rho) <= tol & mard <= tol) |>
    dplyr::arrange(km)
  ref_km <- stab$km[stab$model == ref]
  stab$equivalent <- vapply(stab$km, function(k) {
    all(stab$stable[stab$km >= min(k, ref_km) & stab$km <= max(k, ref_km)])
  }, logical(1))
  ok <- stab$model[stab$equivalent & stab$model %in% sane]
  pick <- if (length(ok)) ok[which.max(stab$km[match(ok, stab$model)])] else ref
  # With an assumed mesh the later stages own decisions.rds; the mesh result is only recorded.
  if (is.na(as.numeric(Sys.getenv("MESH_ASSUMED_KM", "NA")))) {
    d <- read_decisions(s)
    d$mesh_km <- as.numeric(sub(" km", "", pick))
    saveRDS(d, file.path(s$sel_dir, "decisions.rds"))
  }
  res <- list(stage = "mesh", table = st$table, cv = cvp, index = st$index, stability = stab,
              best_cv = cvp$model[which.max(cvp$elpd)], reference = ref, carried = pick,
              decided = Sys.time())
  saveRDS(res, stage_status_file(s, "mesh"))
  message("Stage mesh: reference '", ref, "', carried '", pick, "'")
  invisible(res)
}

make_family <- function(x) {
  switch(x,
         delta_lognormal = sdmTMB::delta_lognormal(),
         delta_gamma = sdmTMB::delta_gamma(),
         delta_lognormal_poisson = sdmTMB::delta_lognormal(type = "poisson-link"),
         delta_gamma_poisson = sdmTMB::delta_gamma(type = "poisson-link"),
         tweedie = sdmTMB::tweedie(),
         stop("Unknown family ", x))
}

spec_formula <- function(d) {
  rhs <- function(terms) paste(c("0", if (d$year) "fyear", terms), collapse = " + ")
  f1 <- stats::as.formula(paste("value ~", rhs(d$terms)))
  if (is.null(d$positive_terms)) return(f1)
  list(f1, stats::as.formula(paste("value ~", rhs(d$positive_terms))))
}

# IID spatiotemporal fields (in at least one component) with a year factor: the structure of an
# index for a state-space assessment model.
is_iid_year <- function(x) {
  st <- unlist(x$spatiotemporal)
  isTRUE(x$year) && all(st %in% c("iid", "off")) && any(st == "iid")
}

# Number of random fields switched on, used to prefer the simpler of two equally good structures.
n_fields <- function(d) {
  per <- function(x) if (is.list(x)) unlist(x) else rep(x, 2)
  sum(per(d$spatial) != "off") + sum(per(d$spatiotemporal) != "off")
}

stage_candidates <- function(stage, s, d) {
  upd <- function(...) utils::modifyList(d, list(...))
  switch(stage,
    fields = list(
      "IID, spatial on (base)" = upd(spatial = "on", spatiotemporal = "iid"),
      "IID, no spatial field" = upd(spatial = "off", spatiotemporal = "iid"),
      "IID in encounter only" = upd(spatial = "on", spatiotemporal = list("iid", "off")),
      "IID in positive only" = upd(spatial = "on", spatiotemporal = list("off", "iid")),
      "IID, spatial field in encounter only" = upd(spatial = list("on", "off"), spatiotemporal = "iid"),
      "No spatiotemporal field" = upd(spatial = "on", spatiotemporal = "off"),
      "AR1 + year" = upd(spatial = "on", spatiotemporal = "ar1"),
      "AR1, no year" = upd(year = FALSE, spatial = "on", spatiotemporal = "ar1"),
      "AR1, no year, no spatial field" = upd(year = FALSE, spatial = "off", spatiotemporal = "ar1"),
      "RW, no year, no spatial field" = upd(year = FALSE, spatial = "off", spatiotemporal = "rw")
    ),
    geometry = list(
      "Isotropic" = d,
      "Anisotropic" = upd(anisotropy = TRUE),
      "Barrier mesh" = upd(barrier = TRUE)
    ),
    fixed = {
      out <- list("All terms" = d)
      for (t in d$terms) out[[paste("Drop", t)]] <- upd(terms = setdiff(d$terms, t))
      ex <- s$set$fixed_extra
      if ("month_smooth" %in% ex && "fmonth" %in% d$terms) {
        out[["Month as a smooth"]] <- upd(terms = sub("^fmonth$", smooth_term("month", s$dt), d$terms))
      }
      # Catchability difference between the survey series: the series mix changes over the
      # years, so an unmodelled difference would bend the trend. Predicted for REFERENCE_SURVEY.
      if ("fsurvey" %in% ex && "fsurvey" %in% names(s$dt) && !"fsurvey" %in% d$terms &&
          dplyr::n_distinct(s$dt$fsurvey) > 1) {
        out[["Add cruise series"]] <- upd(terms = c(d$terms, "fsurvey"))
      }
      # Trawl models grouped within the gear types (gear_model_group()), predicted for
      # REFERENCE_GEAR_MODEL.
      if ("fgear" %in% ex && "fgear" %in% names(s$dt) && "geartype" %in% d$terms &&
          dplyr::n_distinct(s$dt$fgear) > 2) {
        out[["Gear model instead of gear type"]] <- upd(terms = sub("^geartype$", "fgear", d$terms))
      }
      dep <- grep("^s\\(depth", d$terms, value = TRUE)
      if ("quadratic_depth" %in% ex && length(dep)) {
        # sdmTMB needs the same formula in both delta components when it has smooths, so the
        # simpler depth form is tried in both: a quadratic in depth (100 m units).
        out[["Quadratic depth"]] <- upd(terms = c(setdiff(d$terms, dep), "I(depth / 100)", "I((depth / 100)^2)"))
      }
      out
    },
    family = {
      fams <- c("Delta-lognormal" = "delta_lognormal", "Delta-gamma" = "delta_gamma",
                "Delta-lognormal, Poisson link" = "delta_lognormal_poisson",
                "Delta-gamma, Poisson link" = "delta_gamma_poisson", "Tweedie" = "tweedie")
      # The incoming family first: it is the reference of the decision rule.
      fams <- fams[order(fams != d$family)]
      lapply(fams, function(f) upd(family = f))
    },
    stop("Unknown stage ", stage)
  )
}

build_mesh <- function(s, d) {
  m <- sdmTMB::make_mesh(s$dt, xy_cols = c("X", "Y"), cutoff = d$mesh_km)
  if (isTRUE(d$barrier)) {
    m <- sdmTMBextra::add_barrier_mesh(m, barrier_land(s), proj_scaling = 1000)
  }
  m
}

# Land polygon for the barrier mesh, cached in the selection folder: ggOceanMaps may download
# shapefiles, which compute nodes without internet cannot, so the cache is made on the server.
barrier_land <- function(s) {
  f <- file.path(s$sel_dir, "barrier-land.rds")
  if (file.exists(f)) return(readRDS(f))
  land <- ggOceanMaps::basemap_data(data = s$dt, crs = dt_crs)$shapefiles$land
  land <- sf::st_transform(land, dt_crs)
  saveRDS(land, f)
  land
}

run_candidate <- function(species, stage, name, phase, n_workers = 10) {
  s <- stage_setup(species)
  d <- read_decisions(s)
  if (stage == "mesh") {
    spec <- list(cutoff = as.numeric(sub(" km", "", name)))
    args <- list(candidates = stats::setNames(list(spec), name), data = s$dt,
                 formula = stats::as.formula(paste("value ~ 0 + fyear +", paste(s$terms, collapse = " + "))),
                 family = model_family, time = "year", spatial = model_spatial,
                 spatiotemporal = "iid", cache_prefix = "mesh-spacetime")
  } else {
    cand <- stage_candidates(stage, s, d)[[name]]
    if (is.null(cand)) stop("No candidate '", name, "' in stage ", stage)
    args <- list(candidates = stats::setNames(list(list(
                   formula = spec_formula(cand), family = make_family(cand$family),
                   spatial = cand$spatial, spatiotemporal = cand$spatiotemporal,
                   mesh = build_mesh(s, cand))), name),
                 data = s$dt, time = "year", cache_prefix = paste0("v-", stage))
    if (isTRUE(cand$anisotropy)) args$anisotropy <- TRUE
    if (any(unlist(cand$spatiotemporal) %in% c("ar1", "rw")) && length(s$extra_time)) {
      args$extra_time <- s$extra_time
    }
  }
  args <- c(args, list(cache_dir = s$sel_dir, complete_cases = FALSE, n_workers = n_workers,
                       cv = if (phase == "cv") s$cfg$CV_FOLDS %||% 10 else FALSE,
                       fold_ids = if (phase == "cv") s$folds else NULL))
  args$offset <- model_offset
  sel <- do.call(sdmTMB_selection, args)
  print(sel$table)
  # The index of each fitted candidate, cached beside the fit.
  fit <- sel$fits[[1]]
  idx_file <- cache_file(s, args$cache_prefix, name, "-index")
  if (!is.null(fit) && !file.exists(idx_file)) {
    idx <- try(predict_index(fit, s$grid, area = grid_cell_area_nmi2, bias_correct = FALSE))
    if (!inherits(idx, "try-error")) saveRDS(idx, idx_file)
  }
  invisible(sel)
}

# Cache file of a candidate, as sdmTMB_selection() names it. sdmTMBexperiments >= 0.1.13 uses an
# R-version-independent hash; a cache written under the older rlang-hash name is renamed to the
# current name on first use, as sdmTMB_selection() does.
cache_file <- function(s, prefix, name, suffix = "") {
  ns <- asNamespace("sdmTMBexperiments")
  f <- file.path(s$sel_dir, paste0(prefix, "-", ns$.selection_slug(name), suffix, ".rds"))
  if (!file.exists(f) && exists(".legacy_selection_slug", envir = ns)) {
    old <- file.path(s$sel_dir, paste0(prefix, "-", ns$.legacy_selection_slug(name), suffix, ".rds"))
    if (file.exists(old) && old != f) file.rename(old, f)
  }
  f
}

# Read every cached candidate of a stage into one selection-like object.
read_stage <- function(s, stage, names, with_cv = FALSE) {
  prefix <- if (stage == "mesh") "mesh-spacetime" else paste0("v-", stage)
  rd <- function(nm, suffix) {
    f <- cache_file(s, prefix, nm, suffix)
    if (file.exists(f)) readRDS(f) else NULL
  }
  fits <- lapply(names, function(nm) rd(nm, "")$fit)
  cvs <- if (with_cv) lapply(names, function(nm) rd(nm, "-cv")$cv) else NULL
  idx <- lapply(names, function(nm) rd(nm, "-index"))
  names(fits) <- names(idx) <- names
  if (with_cv) names(cvs) <- names
  tab <- purrr::imap_dfr(fits, function(f, nm) {
    if (is.null(f)) return(tibble::tibble(model = nm, converged = FALSE, pdHess = FALSE,
                                          sanity = FALSE, AIC = NA_real_, minutes = NA_real_))
    san <- suppressMessages(try(sdmTMB::sanity(f, silent = TRUE), silent = TRUE))
    tibble::tibble(model = nm, converged = f$model$convergence == 0,
                   pdHess = isTRUE(f$pos_def_hessian),
                   sanity = !inherits(san, "try-error") && isTRUE(san$all_ok),
                   AIC = stats::AIC(f), minutes = NA_real_)
  })
  tab$deltaAIC <- tab$AIC - min(tab$AIC, na.rm = TRUE)
  list(table = tab, fits = fits, cv = cvs, index = idx)
}

stage_status_file <- function(s, stage) file.path(s$sel_dir, paste0("stage-", stage, ".rds"))

# Phase "fit": rank by AIC and write the shortlist. Phase "final": combine with the CV results,
# apply the decision rule and update the decisions.
assemble_stage <- function(species, stage, phase) {
  s <- stage_setup(species)
  d <- read_decisions(s)
  cands <- stage_candidates(stage, s, d)
  if (phase == "fit") {
    st <- read_stage(s, stage, names(cands))
    ok <- st$table$converged & st$table$pdHess
    ranked <- st$table$model[ok][order(st$table$AIC[ok])]
    cv_top_n <- s$set$cv_top_n
    short <- unique(c(head(ranked, cv_top_n), names(cands)[1]))
    if (stage == "fields") {
      # Two selections: the assessment structure among the IID + year candidates (the base model and
      # the best of them by AIC) and the smoothed-index structure among the smoothed candidates
      # (all of them, so that the parsimony rule can reach the simplest).
      iid <- names(cands)[vapply(cands, is_iid_year, logical(1))]
      smo <- names(cands)[vapply(cands, is_smoothed_spec, logical(1))]
      short <- unique(c(names(cands)[1], head(intersect(ranked, iid), cv_top_n), intersect(ranked, smo)))
    }
    # Geometry and family: every candidate, so that the simplest one is always cross-validated.
    if (stage == "geometry") short <- names(cands)
    if (stage == "family") short <- unique(c(names(cands)[1], ranked))
    writeLines(short, file.path(s$sel_dir, paste0("stage-", stage, "-shortlist.txt")))
    return(invisible(short))
  }
  short <- readLines(file.path(s$sel_dir, paste0("stage-", stage, "-shortlist.txt")))
  st <- read_stage(s, stage, names(cands))
  st_cv <- read_stage(s, stage, short, with_cv = TRUE)
  cvp <- cv_paired(list(cv = st_cv$cv), group = cv_groups(s$dt, attr(s$folds, "block_km")))
  best <- cvp$model[which.max(cvp$elpd)]
  pick <- decide_stage(stage, cands, cvp, best, st$table, iid_year_only = s$set$iid_year_only)
  res <- list(stage = stage, table = st$table, cv = cvp, shortlist = short,
              index = st$index, best_cv = best, carried = pick, incoming = names(cands)[1],
              specs = cands, decided = Sys.time())
  d_new <- cands[[pick]]
  if (stage == "fields") {
    # The smoothed-index structure is recorded with the decisions; later stages select the
    # fixed effects, geometry and family on the IID model, and the final report applies them to
    # this structure.
    res$smoothed <- decide_smoothed(cands, cvp, st$table)
    if (!is.na(res$smoothed)) d_new$smoothed <- cands[[res$smoothed]][c("year", "spatial", "spatiotemporal")]
  }
  saveRDS(res, stage_status_file(s, stage))
  saveRDS(d_new, file.path(s$sel_dir, "decisions.rds"))
  message("Stage ", stage, ": best by CV '", best, "', carried '", pick, "'")
  invisible(res)
}

# Decision rules, stated in the validate document. Every stage uses the one-standard-error
# rule (Breiman et al. 1984; Hastie et al. 2009): the candidates whose ELPD is within one
# paired SE of the best form the eligible set, and the simplest eligible candidate is selected.
#   fields    restricted to the IID + year candidates (the structure of an index for a
#             state-space assessment such as SPiCT; SELECTION: IID_YEAR_ONLY) unless switched
#             off; the eligible one with fewest random fields. The smoothed-index structure is selected separately
#             among the smoothed candidates (decide_smoothed()).
#   geometry  isotropic if eligible, otherwise the best.
#   fixed     the eligible candidate with fewest terms (a smooth counts more than a quadratic).
#   family    Tweedie (one component) if eligible; otherwise the incoming family if eligible,
#             otherwise the best. The delta families have the same number of parameters (the
#             Poisson link adds none), so among them the incoming family is the default.
within_one_se <- function(cvp, models) {
  top <- models[which.max(cvp$elpd[match(models, cvp$model)])]
  models[cvp$elpd[match(models, cvp$model)] >= cvp$elpd[cvp$model == top] - se_between(cvp, top, models)]
}

decide_stage <- function(stage, cands, cvp, best, tab, iid_year_only = TRUE) {
  sane <- tab$model[tab$converged & tab$pdHess]
  pw <- attr(cvp, "pointwise")
  grp <- attr(cvp, "group")
  cvp <- cvp[cvp$model %in% sane, ]
  attr(cvp, "pointwise") <- pw
  attr(cvp, "group") <- grp
  ref <- names(cands)[1]
  top <- cvp$model[which.max(cvp$elpd)]
  switch(stage,
    fields = {
      ok <- if (iid_year_only) cvp$model[vapply(cands[cvp$model], is_iid_year, logical(1))] else cvp$model
      if (!length(ok)) return(ref)
      close <- within_one_se(cvp, ok)
      close[which.min(vapply(close, function(m) n_fields(cands[[m]]), numeric(1)))]
    },
    geometry = if (ref %in% within_one_se(cvp, cvp$model)) ref else top,
    fixed = {
      close <- within_one_se(cvp, cvp$model)
      # A smooth counts as more complex than the two quadratic terms that replace it.
      size <- vapply(close, function(m) {
        tm <- cands[[m]]$terms
        # The gear-model factor has more levels than the gear type it replaces.
        length(tm) + 1.5 * sum(grepl("^s\\(", tm)) - 0.5 * sum(grepl("^I\\(", tm)) + 0.5 * ("fgear" %in% tm)
      }, numeric(1))
      close[which.min(size)]
    },
    family = {
      close <- within_one_se(cvp, cvp$model)
      size <- ifelse(vapply(close, function(m) cands[[m]]$family, character(1)) == "tweedie", 1, 2)
      close <- close[size == min(size)]
      if (ref %in% close) ref else close[which.max(cvp$elpd[match(close, cvp$model)])]
    }
  )
}

# Smoothed-index structure: among the converged smoothed candidates (AR1 or random-walk fields,
# no year factor), the one with the fewest parameters within one paired SE of the best of them.
decide_smoothed <- function(cands, cvp, tab) {
  sane <- tab$model[tab$converged & tab$pdHess]
  ok <- intersect(cvp$model[vapply(cands[cvp$model], is_smoothed_spec, logical(1))], sane)
  if (!length(ok)) return(NA_character_)
  close <- within_one_se(cvp, ok)
  close[which.min(vapply(close, function(m) smooth_size_spec(cands[[m]]), numeric(1)))]
}

# Paired SE of the ELPD difference between `ref` and each of `others` (vector), from the
# per-haul log-likelihoods and the block groups kept in the cv_paired() attributes.
se_between <- function(cvp, ref, others) {
  ll <- attr(cvp, "pointwise")
  vapply(others, function(m) {
    if (m == ref) return(0)
    paired_se(ll[[m]] - ll[[ref]], attr(cvp, "group"))
  }, numeric(1))
}

# Stage "grid": the selected model's index on 5 to 200 km prediction grids, with the time to
# compute the index and the size of the grid. Not a model choice: the grid is chosen for
# precision and cost in the validate document.
run_grid_stage <- function(species) {
  s <- stage_setup(species)
  d <- read_decisions(s)
  fin <- readRDS(stage_status_file(s, "family"))
  fit <- read_stage(s, "family", fin$carried)$fits[[1]]
  region <- read_prediction_region(s$cfg, dt_crs)
  if (is.null(region)) stop("No prediction region: run the survey-selection document first.")
  ref_grid <- s$grid
  idx <- lapply(s$set$grid_ladder, function(km) {
    # The grid builder of the fit and report documents, at each resolution.
    g <- build_model_grid(region, s$dt, s$cfg, resolution = km)
    g <- g[g$year %in% ref_grid$year, , drop = FALSE]
    t0 <- Sys.time()
    out <- predict_index(fit, g, area = (km / 1.852)^2, bias_correct = FALSE)
    dplyr::mutate(out, grid_km = km, cells = nrow(g) / dplyr::n_distinct(g$year),
                  index_minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")),
                  grid_mb = as.numeric(utils::object.size(g)) / 2^20)
  })
  res <- list(stage = "grid", index = dplyr::bind_rows(idx), carried_model = fin$carried,
              spec = d, decided = Sys.time())
  saveRDS(res, stage_status_file(s, "grid"))
  invisible(res)
}
