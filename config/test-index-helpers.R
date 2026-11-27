# Synthetic checks of project-template/R/index_helpers.R. Run from the index-wise repository root.
# The model-based checks run only when sdmTMB is installed; the rest need dplyr only.
source("project-template/R/index_helpers.R")

# --- Effort and index year --------------------------------------------------------------
stopifnot(all.equal(swept_area_nmi2(1, 1852), 1),
          identical(effort_mode(list()), "density"),
          is.null(offset_column(list(EFFORT = "density"))),
          identical(offset_column(list(EFFORT = "offset")), "log_swept_area"),
          inherits(try(effort_mode(list(EFFORT = "area")), silent = TRUE), "try-error"))

# Calendar year by default; a July-June season labelled by its start or by its end year.
stopifnot(identical(index_year(c(2020, 2021), c(2, 9)), c(2020L, 2021L)),
          identical(index_year(c(2021, 2021), c(2, 9), 7, "start"), c(2020L, 2021L)),
          identical(index_year(c(2020, 2021), c(9, 2), 7, "end"), c(2021L, 2021L)),
          inherits(try(index_year(2020, NA, 7), silent = TRUE), "try-error"))

# --- Design balance and length coverage -------------------------------------------------
hauls <- data.frame(
  year = rep(2020:2023, each = 10),
  gear = c(rep("trawl", 18), rep("sledge", 2), rep("sledge", 20)),
  haul_id = sprintf("h%02d", 1:40),
  biomass = rep(c(0, 5, 10, 0, 2), 8),
  n_measured = rep(c(0, 3, 0, 0, 4), 8)
)
bal <- design_balance(hauls, "gear")
stopifnot(identical(sort(names(bal$wide)), c("sledge", "trawl")),
          all(bal$counts$year %in% 2020:2023),
          all(bal$shift$flagged))   # gear and year are confounded in this design
cov <- length_coverage(hauls)
stopifnot(all(cov$positive_hauls == 6), all(cov$without_lengths == 2),
          all(abs(cov$share_catch - 20 / 34) < 1e-12))
stopifnot(identical(nrow(subsample_stations(hauls, 0.5)), 20L),
          all(table(subsample_stations(hauls, 0.5)$year) == 5))

# --- Bridging ---------------------------------------------------------------------------
new <- data.frame(year = 2018:2022, est = c(10, 12, 11, 13, 20))
old <- data.frame(year = 2017:2021, est = c(5, 5, 6, 5.5, 6.5))
br <- compare_with_previous(new, old, tolerance = 0.2)
stopifnot(identical(nrow(br$table), 4L), abs(br$terminal_change) < 1e-12,
          length(br$flagged_years) == 0L)
old$est[old$year == 2021] <- 13
stopifnot(2021 %in% compare_with_previous(new, old)$flagged_years)

# --- Index scale (needs sdmTMB) ---------------------------------------------------------
if (requireNamespace("sdmTMB", quietly = TRUE)) {
  set.seed(1)
  d <- subset(sdmTMB::pcod, year %in% 2011:2017)
  d$swept_area <- stats::runif(nrow(d), 0.01, 0.05)
  d$biomass <- d$density * d$swept_area
  d$log_swept_area <- log(d$swept_area)
  d$fyear <- factor(d$year)
  mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 25)
  fit_offset <- sdmTMB::sdmTMB(biomass ~ 0 + fyear, data = d, mesh = mesh,
                               family = sdmTMB::tweedie(), offset = "log_swept_area",
                               spatial = "on", spatiotemporal = "off", time = "year")
  fit_density <- update(fit_offset, formula = density ~ 0 + fyear, offset = NULL)
  grid <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", sort(unique(d$year)))
  grid$fyear <- factor(grid$year, levels = levels(d$fyear))
  i_offset <- predict_index(fit_offset, grid, area = 4)   # qcs_grid cells are 2 km x 2 km
  i_density <- predict_index(fit_density, grid, area = 4)
  # The two effort conventions estimate the same quantity: offset at 0 gives a density.
  stopifnot(all(abs(log(i_offset$est / i_density$est)) < log(1.5)))
  total_area <- 4 * nrow(sdmTMB::qcs_grid)
  chk <- check_index_scale(i_offset, d, total_area, density_col = "density", fit = fit_offset)
  stopifnot(isTRUE(chk$ok), chk$design_ratio > 0.1, chk$design_ratio < 10)
  # A swept area in the wrong unit (width in km times a km^2 -> nmi^2 factor: x 0.54).
  d$log_wrong_area <- log(0.54 * d$swept_area)
  fit_wrong <- update(fit_offset, offset = "log_wrong_area")
  stopifnot(!check_index_scale(predict_index(fit_wrong, grid, area = 4), d, total_area,
                               density_col = "density", fit = fit_wrong)$ok)
  # Predicting catch per mean tow and integrating it as a density: a > 10x design departure.
  i_bug <- sdmTMB::get_index(fit_offset, newdata = grid, area = 4,
                             offset = rep(log(mean(d$swept_area)), nrow(grid)))
  stopifnot(check_index_scale(i_bug, d, total_area, density_col = "density")$design_ratio < 0.1)
  # Station subsampling keeps the offset attached to its rows through update().
  sub <- subsample_stations(transform(d, haul_id = seq_len(nrow(d))), 0.7)
  refit <- refit_on(fit_offset, sub, cutoff = 25)
  stopifnot(identical(nrow(refit$data), nrow(sub)))
  # Jacobian of the family stage (read_stage()): a logit-link delta-gamma fitted to the density
  # and to the catch with a log swept-area offset has log L_density = log L_catch + sum(log A)
  # over the hauls with catch; the deterministic held-out scores of sdmTMB_cv() ("mle-eb") obey
  # the same identity per haul.
  dj <- d
  dj$log_swept_area <- log(dj$swept_area)
  mesh_j <- sdmTMB::make_mesh(dj, c("X", "Y"), cutoff = 30)
  f_d <- sdmTMB::sdmTMB(density ~ 0 + as.factor(year), dj, mesh = mesh_j, family = sdmTMB::delta_gamma(), spatial = "on", spatiotemporal = "off")
  f_o <- sdmTMB::sdmTMB(biomass ~ 0 + as.factor(year), dj, mesh = mesh_j, family = sdmTMB::delta_gamma(), spatial = "on", spatiotemporal = "off", offset = "log_swept_area")
  stopifnot(abs(as.numeric(stats::logLik(f_d)) - as.numeric(stats::logLik(f_o)) - sum(log(dj$swept_area[dj$density > 0]))) < 1e-4)
  if ("predictive" %in% names(formals(sdmTMB::sdmTMB_cv))) {   # sdmTMB with Monte Carlo CV scores
  folds_j <- rep_len(1:3, nrow(dj))
  cv_d <- suppressMessages(sdmTMB::sdmTMB_cv(density ~ 0 + as.factor(year), data = dj, mesh = mesh_j, family = sdmTMB::delta_gamma(), spatial = "on", spatiotemporal = "off", fold_ids = folds_j, predictive = "mle-eb"))
  cv_o <- suppressMessages(sdmTMB::sdmTMB_cv(biomass ~ 0 + as.factor(year), data = dj, mesh = mesh_j, family = sdmTMB::delta_gamma(), spatial = "on", spatiotemporal = "off", fold_ids = folds_j, offset = "log_swept_area", predictive = "mle-eb"))
  pos_j <- cv_o$data$biomass > 0
  stopifnot(max(abs(cv_d$data$cv_loglik - (cv_o$data$cv_loglik + ifelse(pos_j, log(cv_o$data$swept_area), 0)))) < 1e-3)
  }
  message("Model-based index-helper checks passed.")
} else {
  message("sdmTMB not installed: model-based index-helper checks skipped.")
}
# Prediction region, reference levels and per-fit grid years
rd <- data.frame(lon = c(10, 20, 30), lat = c(70, 71, 72), geartype = c("Cod", "Shrimp", "Shrimp"),
                 month = c(2L, 2L, 10L))
stopifnot(identical(attr(restrict_to_region(rd, NULL), "n_outside"), 0L))
if (requireNamespace("sf", quietly = TRUE)) {
  box <- sf::st_as_sfc(sf::st_bbox(c(xmin = 5, ymin = 69, xmax = 25, ymax = 71.5), crs = 4326))
  kept <- restrict_to_region(rd, sf::st_sf(geometry = box))
  stopifnot(nrow(kept) == 2, attr(kept, "n_outside") == 1)
}
stopifnot(reference_gear(rd, list()) == "Shrimp", reference_gear(rd, list(REFERENCE_GEAR = "Cod")) == "Cod",
          reference_month(rd, list()) == 2L, reference_month(rd, list(REFERENCE_MONTH = 8)) == 8L)
fake_fit <- list(time = "year", data = data.frame(year = c(2001, 2003), fyear = factor(c(2001, 2003))))
g <- grid_for_fit(data.frame(year = 2001:2003), fake_fit)
stopifnot(identical(g$year, c(2001L, 2003L)), identical(levels(g$fyear), c("2001", "2003")))

# --- Paired CV standard error with block groups ------------------------------------------
rh <- new.env()
sys.source("project-template/R/report_helpers.R", envir = rh)
d <- c(1, 1, -1, -1, 2, NA)
grp <- c("a", "a", "b", "b", "c", "c")
stopifnot(all.equal(rh$paired_se(d), sqrt(5) * sd(d[1:5])),
          all.equal(rh$paired_se(d, grp), sqrt(3) * sd(c(2, -2, 2))),
          identical(rh$cv_groups(data.frame(X = c(10, 260), Y = c(0, 0), year = 2020), 250),
                    c("0 0 2020", "1 0 2020")))

# --- Stock selection --------------------------------------------------------------------
flat <- list(SPECIES_SLUG = "cod", OUTPUT_DIR = "data/output", OVER_CM = 30)
stopifnot(identical(select_stock(flat)$STOCK_KEY, "cod"),
          identical(select_stock(flat)$OUTPUT_DIR, "data/output/cod"),
          identical(select_stock(modifyList(flat, list(STOCK_SLUG = "cod-n62")))$STOCK_KEY, "cod-n62"))
multi <- list(OUTPUT_DIR = "data/output", OVER_CM = 30, FINAL_MODEL = list(FAMILY = "tweedie", MESH_CUTOFF_KM = 50),
              SPECIES_SETTINGS = list(ling = list(SPECIES_NAME = "Ling", OVER_CM = 67,
                                                  FINAL_MODEL = list(MESH_CUTOFF_KM = 30)),
                                      tusk = list(SPECIES_NAME = "Tusk")))
l <- select_stock(multi, "ling")
t <- select_stock(multi, "tusk")
stopifnot(identical(l$OVER_CM, 67), identical(t$OVER_CM, 30),
          identical(l$FINAL_MODEL, list(FAMILY = "tweedie", MESH_CUTOFF_KM = 30)),   # nested merge
          identical(t$OUTPUT_DIR, "data/output/tusk"), identical(l$STOCK_KEYS, c("ling", "tusk")),
          inherits(try(select_stock(multi), silent = TRUE), "try-error"),       # key needed
          inherits(try(select_stock(multi, "cod"), silent = TRUE), "try-error"))

# The reason for a dropped month term names the sampled months with few positive hauls.
mo <- rep(c(1:3, 5:8), each = 20)
pos <- mo %in% 1:3 | (mo == 8 & rep(1:20, 7) <= 15)
reason <- month_term_reason(mo, pos, "ling")   # "... each of May–July caught ling, ..."; the dash depends on the locale
stopifnot(startsWith(reason, "fewer than 10 hauls in each of May"),
          grepl("July caught ling, so a month term", reason, fixed = TRUE),
          !grepl("January|August", reason),
          identical(month_term_reason(mo, rep(TRUE, length(mo)), "ling"),
                    "a month term could not be estimated in the first fits"))

# Every delta component needs a year factor or a spatiotemporal field.
f_year <- value ~ 0 + fyear + s(depth)
f_none <- value ~ 0 + s(depth)
stopifnot(isTRUE(check_temporal_terms(f_year, list("off", "iid"))),
          isTRUE(check_temporal_terms(f_none, "ar1")),
          isFALSE(check_temporal_terms(f_none, list("off", "iid"), stop_on_fail = FALSE)),
          isFALSE(check_temporal_terms(list(f_year, f_none), "off", stop_on_fail = FALSE)),
          inherits(try(check_temporal_terms(f_none, "off"), silent = TRUE), "try-error"))

# Cruise series with fewer than MIN_SERIES_YEARS years are grouped into Other.
local({
  `%||%` <- function(a, b) if (is.null(a)) b else a
  env <- new.env()
  sys.source("project-template/R/compile_functions.R", envir = env)
  st <- data.frame(cruiseseries = c(rep("A", 3), rep("B", 2), "Other"), startyear = c(2001:2003, 2001, 2002, 2001))
  out <- suppressMessages(env$lump_short_series(st, 3))
  stopifnot(identical(out$cruiseseries, c("A", "A", "A", "Other", "Other", "Other")))
})

# Effective trawl widths: GEAR_WIDTH for every gear without its own entry in GEAR_WIDTHS.
gn <- c("Reketrål, Campelen 1800, Rs", "Alfredo III", "Konsumtrål 60", "Skjærgårdstrål", "Skjærgårdstrål")
gt <- c("Shrimp", "Cod", "Cod", "Cod", "Other")
stopifnot(identical(gear_width_m(gn, gt, list(GEAR_WIDTH = 25)), rep(25, 5)),
          identical(gear_width_m(gn, gt, list(GEAR_WIDTH = 25, GEAR_WIDTHS = list(Alfredo = 47, `Konsum 60` = 53, `Other cod` = 51))),
                    c(25, 47, 53, 51, 25)),
          identical(gear_width_m(gn, gt, list(GEAR_WIDTH = 25), widths = list(Alfredo = 78))[2], 78),
          inherits(try(gear_width_m(gn, gt, list(GEAR_WIDTH = "per_gear")), silent = TRUE), "try-error"))

# Report effort: offset for a Poisson-link family under "auto", the selection's EFFORT otherwise.
local({
  `%||%` <- function(a, b) if (is.null(a)) b else a
  env <- new.env()
  env$effort_mode <- effort_mode
  sys.source("project-template/R/report_helpers.R", envir = env)
  stopifnot(identical(env$report_effort(list(), "delta_gamma_poisson_link"), "offset"),
            identical(env$report_effort(list(), "delta_gamma"), "density"),
            identical(env$report_effort(list(EFFORT = "offset"), "tweedie"), "offset"),
            identical(env$report_effort(list(REPORT_EFFORT = "density"), "delta_gamma_poisson_link"), "density"),
            inherits(try(env$report_effort(list(REPORT_EFFORT = "x"), "tweedie"), silent = TRUE), "try-error"),
            # The selection's effort (FINAL_MODEL$EFFORT) wins over the Poisson-link rule.
            identical(env$report_effort(list(FINAL_MODEL = list(EFFORT = "density")), "delta_gamma_poisson_link"), "density"),
            identical(env$report_effort(list(FINAL_MODEL = list(EFFORT = "offset")), "delta_gamma"), "offset"))
  # A collapsed smooth (only se_magnitude_ok fails, an sd__s() below 0.01) counts as a pass.
  san <- list(hessian_ok = TRUE, se_magnitude_ok = FALSE, all_ok = FALSE)
  rp <- data.frame(term = c("range", "sd__s(depth)"), estimate = c(50, 5e-4))
  # The assessment structure needs IID spatiotemporal fields in every component.
  stopifnot(isTRUE(env$is_assessment_spec(list(year = TRUE, spatiotemporal = "iid"))),
            isTRUE(env$is_assessment_spec(list(year = TRUE, spatiotemporal = list("iid", "iid")))),
            isFALSE(env$is_assessment_spec(list(year = TRUE, spatiotemporal = list("iid", "off")))),
            isFALSE(env$is_assessment_spec(list(year = FALSE, spatiotemporal = "iid"))),
            identical(env$stage_set(list(stage = "fields", specs = list(a = list(year = TRUE, spatiotemporal = list("off", "iid")))), "a"), "Other"))
  stopifnot(isTRUE(env$sanity_collapsed_smooth(san, rp)),
            isFALSE(env$sanity_collapsed_smooth(san, transform(rp, estimate = c(50, 0.5)))),
            isFALSE(env$sanity_collapsed_smooth(modifyList(san, list(hessian_ok = FALSE)), rp)),
            isFALSE(env$sanity_collapsed_smooth(NULL, rp)))
})

message("Synthetic index-helper checks passed.")
