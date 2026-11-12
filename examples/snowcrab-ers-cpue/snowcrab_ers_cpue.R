# Simplified snow crab ERS CPUE example — synthetic data, three model engines.
#
# The structure follows a trap-fishery logbook (ERS) CPUE index of the snow crab type: haul-level
# positive catches with traps and soak time as effort, season day, depth, a vessel random
# intercept, a core-fleet filter, and an index on a fixed grid over the fished area. The data
# are SIMULATED here with a known abundance trend, so the indices can be compared with the
# truth. No real logbook data, vessels or positions are used: coordinates are in km on an
# arbitrary synthetic shelf.
#
# Run from the index-wise repository root:  Rscript examples/snowcrab-ers-cpue/snowcrab_ers_cpue.R
# Needs: dplyr, glmmTMB, mgcv, sdmTMB (and splines, part of base R). Runs in a few minutes.

source("project-template/R/cpue_helpers.R")
suppressPackageStartupMessages({ library(dplyr); library(splines) })
set.seed(2015)

# --- 1. A synthetic shelf and stock -----------------------------------------------------
years <- 2015:2025
truth_B <- c(1.0, 1.4, 1.9, 2.3, 2.4, 2.2, 1.8, 1.5, 1.3, 1.2, 1.1)   # true abundance trend

shelf <- expand.grid(x = seq(1.25, 198.75, 2.5), y = seq(1.25, 148.75, 2.5))
shelf$depth <- 180 + 1.2 * shelf$x + 25 * sin(shelf$y / 25)          # 180-450 m
habitat <- function(depth) exp(-(depth - 300)^2 / (2 * 70^2))
# Two aggregations: a fixed one and one that moves north-east over the years.
pattern <- function(x, y, t) {
  k <- (t - min(years)) / diff(range(years))
  exp(-((x - 70)^2 + (y - 60)^2) / (2 * 25^2)) +
    1.2 * exp(-((x - 90 - 50 * k)^2 + (y - 40 - 50 * k)^2) / (2 * 20^2))
}
shelf_mean <- sapply(years, function(t) mean(pattern(shelf$x, shelf$y, t) * habitat(shelf$depth)))
density_at <- function(x, y, depth, t) {
  i <- t - min(years) + 1          # t may be a vector (one year per point)
  truth_B[i] * pattern(x, y, t) * habitat(depth) / shelf_mean[i]   # shelf mean = B_t
}

# --- 2. A synthetic fleet ---------------------------------------------------------------
# 30 vessels; half fish from the start, half enter later and are more efficient (a fleet
# composition change that biases nominal CPUE). Some vessels fish only briefly.
fleet <- data.frame(
  vessel_id = sprintf("V%02d", 1:30),
  entry = c(rep(2015, 15), sample(2016:2022, 15, replace = TRUE)),
  q = exp(rnorm(30, 0, 0.3)) * c(rep(1, 15), rep(1.4, 15)),
  records_per_year = c(rep(60, 25), rep(8, 5)),
  vessel_length = round(runif(30, 30, 60))
)
fleet$exit <- pmin(2025, fleet$entry + sample(c(1, 4, 8, 12), 30, replace = TRUE,
                                              prob = c(.1, .2, .3, .4)))

# Fishers search: each haul is placed at a shelf cell drawn with probability proportional to
# density^0.7 (they find aggregations, not the average), within the fishing ground x < 170 km.
ground <- shelf[shelf$x < 170, ]
haul_records <- lapply(seq_len(nrow(fleet)), function(i) {
  v <- fleet[i, ]
  do.call(rbind, lapply(v$entry:v$exit, function(t) {
    n <- rpois(1, v$records_per_year)
    if (n == 0) return(NULL)
    w <- density_at(ground$x, ground$y, ground$depth, t)^0.7
    cell <- sample.int(nrow(ground), n, replace = TRUE, prob = w)
    data.frame(vessel_id = v$vessel_id, year = t,
               x = ground$x[cell] + runif(n, -1.25, 1.25),
               y = ground$y[cell] + runif(n, -1.25, 1.25),
               depth = ground$depth[cell],
               yday = sort(sample(1:120, n, replace = TRUE)),
               traps = sample(80:420, n, replace = TRUE),
               soak = rlnorm(n, log(48), 0.5),           # hours
               q = v$q, vessel_length = v$vessel_length)
  }))
})
hauls <- do.call(rbind, haul_records)

# Expected catch: catchability x density x traps^0.8 x saturating soak x declining season.
mu <- with(hauls, q * density_at(x, y, depth, year) * 40 * (traps / 250)^0.8 *
             (1 - exp(-soak / 30)) * exp(-0.004 * (yday - 30)))
hauls$catch <- rgamma(nrow(hauls), shape = 1 / 0.6^2, rate = 1 / (0.6^2 * mu))
hauls$catch[sample.int(nrow(hauls), 20)] <- hauls$catch[sample.int(nrow(hauls), 20)] * 1000  # unit errors
hauls$effort <- hauls$traps

# --- 3. Record preparation --------------------------------------------------------------
hauls <- cpue_vessel_activity(hauls)
cascade <- cpue_filter_cascade(hauls, list(
  "positive catch"         = quote(catch > 0),
  "traps 100-400"          = quote(traps >= 100 & traps <= 400),
  "soak time < 21 days"    = quote(soak < 21 * 24),
  "catch 10-5000 kg"       = quote(catch >= 10 & catch <= 5000),
  "vessel >= 3 years"      = quote(years_active >= 3),
  "vessel >= 100 records"  = quote(records_total >= 100)
))
print(cascade$log)

d <- cascade$data |>
  mutate(vessel_id = factor(vessel_id), fyear = factor(year),
         log_traps = log(traps), soak_std = (soak - mean(soak)) / sd(soak),
         yday_std = (yday - mean(yday)) / sd(yday), depth_std = (depth - mean(depth)) / sd(depth))

# Reference conditions: 250 traps, mean soak, early season (day 30), mean depth.
reference <- list(log_traps = log(250), soak_std = 0,
                  yday_std = (30 - mean(d$yday)) / sd(d$yday), depth_std = 0)

# Prediction grid: the fished domain only (convex hull of the hauls), one row per cell and year.
hull <- grDevices::chull(d$x, d$y)
in_hull <- function(px, py) {
  hx <- d$x[hull]; hy <- d$y[hull]; n <- length(hx); inside <- logical(length(px))
  j <- n
  for (i in seq_len(n)) {   # ray casting
    cross <- ((hy[i] > py) != (hy[j] > py)) &
      (px < (hx[j] - hx[i]) * (py - hy[i]) / (hy[j] - hy[i]) + hx[i])
    inside <- xor(inside, cross)
    j <- i
  }
  inside
}
cells <- shelf[in_hull(shelf$x, shelf$y), ]
grid <- merge(cells, data.frame(year = years)) |>
  mutate(fyear = factor(year, levels = levels(d$fyear)),
         depth_std = (depth - mean(d$depth)) / sd(d$depth),
         log_traps = reference$log_traps, soak_std = 0, yday_std = reference$yday_std,
         vessel_id = factor(NA, levels = levels(d$vessel_id)))
cell_area <- 2.5^2   # km^2

# The truth on the same domain: total abundance over the fished cells per year.
truth <- data.frame(year = years, est = sapply(years, function(t)
  sum(density_at(cells$x, cells$y, cells$depth, t)) * cell_area))

# --- 4. Three engines -------------------------------------------------------------------
# (a) glmmTMB GLMM: year effect, effort as a covariate (estimated slope), splines, vessel RE.
fit_glmm <- glmmTMB::glmmTMB(
  catch ~ 0 + fyear + log_traps + ns(soak_std, df = 3) + ns(yday_std, df = 3) +
    ns(depth_std, df = 3) + (1 | vessel_id),
  data = d, family = Gamma(link = "log"))
idx_glmm <- cpue_year_index(fit_glmm, cpue_newdata(d, reference))
cat("glmmTMB effort slope (1 = catch proportional to traps):",
    round(glmmTMB::fixef(fit_glmm)$cond[["log_traps"]], 2), "\n")

# (b) mgcv GAMM: as (a) plus a spatial smooth and a space-year interaction, vessel as a
# random-effect smooth; area-weighted over the fished grid.
fit_gam <- mgcv::bam(
  catch ~ fyear + log_traps + s(soak_std, k = 4) + s(yday_std, k = 4) + s(depth_std, k = 4) +
    s(x, y, k = 40) + ti(x, y, year, d = c(2, 1), k = c(15, 4)) + s(vessel_id, bs = "re"),
  data = d, family = Gamma(link = "log"))   # discrete = TRUE fits faster but its predict()
                                            # does not return the lpmatrix the index needs
idx_gam <- cpue_gam_area_index(fit_gam, grid, area = cell_area, exclude = "s(vessel_id)",
                               nsim = 200)

# (c) sdmTMB spatio-temporal GLMM: spatial and IID spatiotemporal fields, vessel RE, the
# index integrated over the fished grid.
mesh <- sdmTMB::make_mesh(d, c("x", "y"), cutoff = 10)
fit_sdm <- sdmTMB::sdmTMB(
  catch ~ 0 + fyear + log_traps + s(soak_std, k = 4) + s(yday_std, k = 4) +
    s(depth_std, k = 4) + (1 | vessel_id),
  data = d, mesh = mesh, family = Gamma(link = "log"),
  spatial = "on", spatiotemporal = "iid", time = "year")
print(sdmTMB::sanity(fit_sdm))
idx_sdm <- cpue_sdm_index(fit_sdm, grid, area = cell_area)

# --- 5. Compare with the truth ----------------------------------------------------------
rel <- function(x) x / mean(x)
nominal <- cpue_nominal(d)
comparison <- data.frame(
  year = years,
  truth = rel(truth$est),
  nominal = nominal$index,
  glmmTMB = idx_glmm$index,
  mgcv = idx_gam$index,
  sdmTMB = idx_sdm$index
)
print(round(comparison, 2))
score <- sapply(comparison[-(1:2)], function(x) c(
  correlation = cor(log(x), log(comparison$truth)),
  mean_abs_log_error = mean(abs(log(x / comparison$truth)))))
print(round(score, 3))

# Residual dispersion by vessel-year: > 1 means records of a vessel within a year are more
# alike than the model assumes, and the GLMM intervals are too narrow.
if (requireNamespace("DHARMa", quietly = TRUE)) {
  print(cpue_dharma_groups(fit_glmm, list(
    records = NULL, vessel = d$vessel_id, `vessel-year` = interaction(d$vessel_id, d$year))))
}

invisible(list(comparison = comparison, score = score, filter_log = cascade$log))
