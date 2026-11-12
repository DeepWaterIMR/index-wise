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
  message("Model-based index-helper checks passed.")
} else {
  message("sdmTMB not installed: model-based index-helper checks skipped.")
}
message("Synthetic index-helper checks passed.")
