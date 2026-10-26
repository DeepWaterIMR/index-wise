# Synthetic checks of project-template/R/cpue_helpers.R. Run from the index-wise repository root.
# Needs dplyr and mgcv (a recommended package shipped with R); glmmTMB checks run if installed.
# The full three-engine example is examples/snowcrab-ers-cpue/snowcrab_ers_cpue.R.
source("project-template/R/cpue_helpers.R")
set.seed(1)

# --- Records ----------------------------------------------------------------------------
d <- data.frame(
  vessel_id = rep(c("A", "B", "C"), times = c(40, 30, 10)),
  year = c(rep(2020:2023, each = 10), rep(2021:2023, each = 10), rep(2023, 10)),
  vessel_length = c(rep(12, 20), rep(16, 20), rep(20, 30), rep(9, 10))
)
d$effort <- sample(100:400, nrow(d), replace = TRUE)
d$catch <- rgamma(nrow(d), 4, 4 / (2 * d$effort^0.8)) * c(1, 1.5, 0.7)[match(d$vessel_id, c("A", "B", "C"))]

act <- cpue_vessel_activity(d)
stopifnot(all(act$years_active[act$vessel_id == "A"] == 4),
          all(act$records_total[act$vessel_id == "C"] == 10),
          all(act$records_year == 10))

ch <- cpue_vessel_changes(d)
stopifnot(identical(sort(unique(as.character(ch$vessel_id))), c("A", "A_new", "B", "C")),
          all(ch$vessel_id[ch$vessel_id_original == "A" & ch$year >= 2022] == "A_new"))

cas <- cpue_filter_cascade(act, list("effort 150-400" = quote(effort >= 150),
                                     ">= 2 years" = quote(years_active >= 2)))
stopifnot(identical(cas$log$step, c("all records", "effort 150-400", ">= 2 years")),
          cas$log$records[1] == nrow(d), all(diff(cas$log$records) <= 0),
          !"C" %in% cas$data$vessel_id)

rec <- cpue_reconcile(d, data.frame(year = 2020:2023, landed = c(1e4, 2e4, 2e4, 3e4)))
stopifnot(identical(nrow(rec), 4L), all(rec$coverage > 0))
stopifnot(all(abs(mean(cpue_nominal(d)$index) - 1) < 1e-12))

# --- Prediction reference and AIC scale -------------------------------------------------
d$vessel_id <- factor(d$vessel_id); d$fyear <- factor(d$year)
d$log_effort <- log(d$effort)
nd <- cpue_newdata(d, list(log_effort = log(250), vessel_length = NULL))
stopifnot(identical(nrow(nd), 4L), all(is.na(nd$vessel_id)), all(nd$log_effort == log(250)),
          all(nd$vessel_length == stats::median(d$vessel_length)))

m_log <- stats::lm(log(catch / effort) ~ fyear, data = d)
m_ratio <- stats::glm(catch / effort ~ fyear, family = Gamma(link = "log"), data = d)
m_catch <- stats::glm(catch ~ fyear + offset(log_effort), family = Gamma(link = "log"), data = d)
# Gamma(CPUE) and Gamma(catch) with a log-effort offset are the same model: equal on the catch scale.
stopifnot(abs(cpue_aic_catch_scale(m_ratio, d, "cpue") -
              cpue_aic_catch_scale(m_catch, d, "catch")) < 1e-6,
          is.finite(cpue_aic_catch_scale(m_log, d, "log_cpue")))

# --- Indices from fits ------------------------------------------------------------------
d$x <- runif(nrow(d), 0, 10); d$y <- runif(nrow(d), 0, 10)
gam_fit <- mgcv::gam(catch ~ fyear + log_effort + s(x, y, k = 10) + s(vessel_id, bs = "re"),
                     data = d, family = Gamma(link = "log"), method = "REML")
nd_xy <- transform(nd, x = 5, y = 5)   # newdata needs every covariate, coordinates included
yi <- cpue_year_index(gam_fit, nd_xy, exclude = "s(vessel_id)")
stopifnot(identical(nrow(yi), 4L), all(yi$lwr < yi$est & yi$est < yi$upr),
          abs(mean(yi$index) - 1) < 1e-12)
grid <- merge(expand.grid(x = seq(0.5, 9.5, 1), y = seq(0.5, 9.5, 1)), data.frame(year = 2020:2023))
grid$fyear <- factor(grid$year, levels = levels(d$fyear))
grid$log_effort <- log(250)
grid$vessel_id <- factor(NA, levels = levels(d$vessel_id))
ai <- cpue_gam_area_index(gam_fit, grid, area = 1, exclude = "s(vessel_id)", nsim = 100)
stopifnot(identical(nrow(ai), 4L), all(ai$lwr <= ai$est & ai$est <= ai$upr))
# Without a space-year interaction the area-weighted and the year-effect index have one shape.
stopifnot(all(abs(ai$index - yi$index) < 1e-8))

pg <- cpue_pearson_groups(gam_fit, list(vessel = d$vessel_id, year = d$fyear))
stopifnot(identical(pg$grouping, c("vessel", "year")), all(is.finite(pg$dispersion)))

boot <- cpue_vessel_bootstrap(d, function(db) {
  f <- stats::glm(catch ~ 0 + fyear + log_effort, family = Gamma(link = "log"), data = db)
  data.frame(year = 2020:2023, est = exp(stats::coef(f)[1:4]))
}, n_boot = 5)
# With three vessels some draws hold a single vessel and cannot be fitted: they are counted.
stopifnot(length(unique(boot$boot)) + attr(boot, "n_failed") == 5L,
          all(table(boot$boot) == 4L))

if (requireNamespace("glmmTMB", quietly = TRUE)) {
  g <- glmmTMB::glmmTMB(catch ~ 0 + fyear + log_effort + (1 | vessel_id), data = d,
                        family = Gamma(link = "log"))
  gi <- cpue_year_index(g, nd)
  stopifnot(identical(nrow(gi), 4L), all(is.finite(gi$se)),
            identical(length(cpue_year_contrast_se(g)), 4L))
  message("glmmTMB CPUE-helper checks passed.")
}
message("Synthetic CPUE-helper checks passed.")
