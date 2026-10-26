# Standardising CPUE — models, indices and their checks

Read `cpue.md` first: the data decide most of what follows. This file covers the model: what
the response and effort term are, which engine to use, how to turn a fit into an index, and
which checks the index needs before an assessment uses it. The helpers named here are in the
project's `R/cpue_helpers.R`; `examples/snowcrab-ers-cpue/` runs all three engines on synthetic
data with a known trend.

## Response, family and effort

| Response | Family | Effort | Notes |
|---|---|---|---|
| catch per record (positive) | `Gamma(link = "log")` | `log(effort)` as covariate or offset | the default for directed-fishery logbooks |
| `log(catch / effort)` | Gaussian | in the response | lognormal CPUE; the classic GLM |
| catch / effort | Gamma | in the response | equals Gamma catch with a `log(effort)` offset |
| catch incl. recorded zeros | Tweedie, or a delta/hurdle family | covariate or offset | only where zeros are recorded and mean "fished, caught none" |

- **Effort as an offset assumes catch proportional to effort.** As a covariate, `log(effort)`
  has an estimated slope; 1 means proportionality, < 1 means saturation (traps competing,
  gear filling). Fit the covariate version and report the slope; keep the offset only if the
  slope is close to 1. A second effort dimension (soak or tow time) usually enters as a smooth.
- **Compare responses on the catch scale.** AIC of `log(CPUE)`, `CPUE` and `catch` models are
  on different scales; `cpue_aic_catch_scale()` applies the change-of-variable correction
  (add $2\sum\log c_i$ for $\log(c/E)$, $2\sum\log E_i$ for $c/E$), the same Jacobian argument
  as in `model-selection.md`. Only compare fits to identical records.
- A lognormal model's back-transformation bias ($\sigma^2/2$) is constant across years with a
  common variance, so a relative index is unaffected; it matters for absolute values only.

## The year effect and the standardised covariates

Fit the year as a factor (`fyear`, a precomputed column) with the intercept removed
(`0 + fyear`), and covariates that change catch rate without changing abundance:

- **Effort**: `log(effort)`, soak or tow time (smooth).
- **Season**: day of year, or day within the vessel's season; a cyclic spline
  (`s(month, bs = "cc")` with `knots`) when the season wraps around the year.
- **Vessel**: a random intercept `(1 | vessel_id)`, so vessels entering and leaving the fleet do
  not move the index. Vessel length or engine power as fixed effects when the random effect is
  not estimable or when they are needed for prediction.
- **Space**: an area factor or random effect (statistical area, stratum), or a spatial model
  (below).
- **Depth**, **gear specification** (number of trawls, mesh, trap type), **time of day**.

**Not**: covariates that trend over time by construction (years of experience, cumulative
effort), or that respond to abundance (catch of the previous haul, trip length when trips end
when the hold is full). They are confounded with the year effect.

The index is the prediction at **reference conditions** — one unit or a standard amount of
effort, a reference season day, mean covariates, population level (random effects excluded) —
for each year: `cpue_newdata()` builds it, with grouping columns set to `NA`.

## Within-year correlation: the intervals are usually too narrow

Records of one vessel in one year, or of one area in one year, share conditions the model does
not see (the skipper that year, local aggregations). Treated as independent, they make the
year effects look far more precise than they are. Check and correct in this order:

1. **Grouped residual dispersion**: residuals summed by vessel-year, area-year and
   area-year-month. Dispersion ≈ 1 (or below, for conditional residuals) for groups the model
   contains, > 1 for correlated groups the model lacks. `cpue_pearson_groups()` uses Pearson
   residuals and works for all three engines; `cpue_dharma_groups()` uses DHARMa simulation
   residuals (glmmTMB; for a `gam`, DHARMa needs the mgcViz package).
2. **Year-level random interactions**: `(1 | vessel_year)` and `(1 | area_year)`, as
   precomputed factor columns. They absorb the shared deviations; the year effects widen. If an
   area factor is effectively one location, an area-year term duplicates an area-specific trend
   and absorbs signal: drop one.
3. **Vessel bootstrap** (`cpue_vessel_bootstrap()`): resample vessels with all their records,
   stratified by each vessel's main area, refit, and read the interval from the spread. It does
   not depend on the model's correlation assumptions; correlation between vessels in the same
   area-year is not resampled, so it is a lower bound.
4. For the trend itself, report `cpue_year_contrast_se()`: the SE of each year relative to the
   series mean, without the uncertainty all years share.

## Three engines

### glmmTMB — the generalized linear mixed model

```r
fit <- glmmTMB::glmmTMB(
  catch ~ 0 + fyear + log_effort + splines::ns(soak_std, df = 3) + splines::ns(yday_std, df = 3) +
    (1 | vessel_id) + (1 | area) + (1 | vessel_year),
  data = d, family = Gamma(link = "log"))
index <- cpue_year_index(fit, cpue_newdata(d, reference, groups = c("vessel_id", "area", "vessel_year")))
```

Fast, many records, crossed random effects. Predict with `re.form = NA` (population level) and
`allow.new.levels = TRUE` (what `cpue_year_index()` does). **Build every grouping factor as a
column**; an interaction written in the formula (`(1 | vessel:year)`) turns `NA` in newdata into
a new level and, with conditional prediction, adds its variance to the index. Splines through
`splines::ns()`; check that `ns(x, k = 3)` is not silently `knots = 3` (partial matching).
Spatial structure only through area factors: the year effect then weights areas by where
fishing happened, which is how hyperstability enters (`cpue.md`). Area-specific trends:
`fyear:farea` fixed or an AR1 random field over years within area
(`ar1(fyear + 0 | farea)`).

### mgcv — the generalized additive mixed model

```r
fit <- mgcv::bam(
  catch ~ fyear + log_effort + s(soak_std, k = 4) + s(yday_std, k = 4) + s(depth_std, k = 4) +
    s(x, y, k = 40) + ti(x, y, year, d = c(2, 1), k = c(15, 4)) + s(vessel_id, bs = "re"),
  data = d, family = Gamma(link = "log"))
index <- cpue_gam_area_index(fit, grid, area = cell_area, exclude = "s(vessel_id)")
```

Smooths of anything, random effects as `bs = "re"` smooths, a spatial smooth `s(x, y)` and a
space-time interaction (`ti(x, y, year)`, or `s(x, y, by = fyear)` for few years). The index is
area-weighted: `cpue_gam_area_index()` predicts every grid cell at reference conditions,
excluding the vessel smooth, sums density × cell area per year, and takes intervals from draws
of the coefficients (`Vp`, the Bayesian covariance). Without a space-time term the area index
has the same shape as the year effect. `bam(discrete = TRUE)` fits faster, but its `predict()`
does not return the linear-predictor matrix the index needs; refit without it for the index.
`family = tw()` for zero-inflated catch.

### sdmTMB — the spatio-temporal GLMM

```r
mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 10)
fit <- sdmTMB::sdmTMB(
  catch ~ 0 + fyear + log_effort + s(soak_std, k = 4) + s(yday_std, k = 4) + s(depth_std, k = 4) +
    (1 | vessel_id),
  data = d, mesh = mesh, family = Gamma(link = "log"),
  spatial = "on", spatiotemporal = "iid", time = "year")
index <- cpue_sdm_index(fit, grid, area = cell_area, bias_correct = TRUE)
```

Gaussian random fields carry the spatial and spatio-temporal structure, so a shift of the stock
or the fleet between areas is modelled rather than averaged over. The index integrates the
prediction over a fixed grid, with the vessel random intercept dropped (`re_form_iid = ~0`) and
any offset at 0 (one effort unit), which `cpue_sdm_index()` handles. Everything in `sdmtmb.md`
applies (km coordinates, `sanity()`, mesh resolution, `extra_time`, year factor as a column).
Specific to CPUE:

- **Year effect plus field.** `0 + fyear` with an IID field gives each year its own mean and its
  own spatial deviations; with AR1 the deviations are correlated between years. Without any
  spatio-temporal field every sub-area of the grid gets the same trend.
- **Choose `spatiotemporal` by AIC among fits that pass `sanity()`**, and show the index of each
  candidate: IID and AR1 often differ little in AIC and more in the terminal year.
- **Offsets**: pass `offset = "log_effort"` as a column name; for an estimated effort slope use
  the covariate instead.
- A Gamma model on positive catches has one linear predictor; a delta family (with recorded
  zeros) lets occurrence and catch rate have separate fields.

## The prediction domain: where the index is defined

A spatial model predicts everywhere on its grid, including cells nobody fished in a given year,
or ever. With a log link, extrapolated cells can dominate the sum; assuming that unfished cells
behave like fished ones produces hyperdepletion or hyperstability by construction (Walters
[2003](https://doi.org/10.1139/f03-152)). Define the grid as the **fished domain** and state it:

- the convex hull (or a concave hull) of the records used, clipped to the management area and
  to the depth range of the data (see `sdmtmb.md` on grid depth);
- or a **core area** where fishing occurred in most years, with the full-hull index as a
  sensitivity;
- for strata (fjords, management units), predict per stratum from one fit and aggregate; a
  stratum with few records per year inherits its trend from the shared year effect and the
  fields.

An alternative weighting uses survey density: each cell's predicted CPUE weighted by the survey
model's predicted density in that cell, so the index weights areas by where the stock is rather
than by area. It ties the CPUE index to the survey model; use it as a sensitivity.

## Selection and diagnostics

Use the comparability rules of `model-selection.md`: candidates on identical records,
comparable likelihood scales, the winner read from the table, the gap stated when the carried
model is not the winner. Then:

- **Fixed effects by AIC** with the random effects fixed, then the random effects, then (sdmTMB)
  the spatio-temporal field and the mesh. Show the index of every candidate: a term that changes
  AIC but not the index is not worth arguing about.
- **Covariate associations** before fitting (Cramér's V, correlation ratio, |r|): strongly
  associated covariates (vessel length and engine power; vessel and area) cannot be separated.
- **Residuals**: DHARMa quantile residuals (glmmTMB, mgcv; sdmTMB via `simulate(type =
  "mle-mvn")` and `dharma_residuals()`), against fitted values, year, vessel, space and each
  covariate; a semivariogram of non-spatial GLMM residuals shows whether a spatial model is
  needed.
- **Grouped dispersion** and the vessel bootstrap (above).

## Sensitivity analyses

Each is a refit with one setting changed; collect the indices, not just the AICs.

- **Filters**: every threshold of the cascade (vessel years active, records per vessel-year,
  lifetime records, catch and effort ranges), one at a time.
- **Retrospective peels** (drop final years) and **forward peels** (drop first years).
- **Final-month retrospective**: refit with each year's data cut at the month the assessment
  data end, to see how much the incomplete terminal year moves the index.
- **Domain**: core area vs hull; inside vs outside a management area.
- **Data-source breaks**: one index across the break with a source effect, two indices with
  separate catchabilities, or the newer source aggregated to the older unit.
- **Station-level subsampling** (as in the survey robustness section) to see how the interval
  scales with the number of records.

## Into the assessment

Export `year, est, lwr, upr, se` with `se` on the log scale through
`build_assessment_index_handoff()`, the index **relative** to its mean, and metadata: units
("relative CPUE"), the fleet and area it represents, its timing within the year (mid-season of
the fishery, not of the calendar), and any break that needs separate catchabilities. If the
assessment uses the SEs as relative weights (e.g. SPiCT `stdevfacI`), say whether they come
from the model or from the bootstrap. Compare the CPUE trend with the survey index of the same
component and explain divergence before both enter one model.

## References

- Hoyle, S. D., *et al.* 2024. Catch per unit effort modelling for stock assessment: a summary of
  good practices. Fisheries Research, 269: 106860.
  <https://doi.org/10.1016/j.fishres.2023.106860>
- Maunder, M. N., and Punt, A. E. 2004. Standardizing catch and effort data: a review of recent
  approaches. Fisheries Research, 70: 141–159. <https://doi.org/10.1016/j.fishres.2004.08.002>
- Walters, C. 2003. Folly and fantasy in the analysis of spatial catch rate data. Canadian
  Journal of Fisheries and Aquatic Sciences, 60: 1433–1436. <https://doi.org/10.1139/f03-152>
