# sdmTMB essentials for survey indices

[sdmTMB](https://github.com/sdmTMB/sdmTMB) fits spatial and spatiotemporal GLMMs with Gaussian
random fields (via TMB + a SPDE mesh). Docs: <https://pbs-assess.github.io/sdmTMB/>. **Read
the docs before writing model code — do not guess the API.** This file is the minimum you
need for a survey index; the helpers in `sdmtmbexperiments.md` wrap most of the tedious parts.

## The model

A survey index model predicts density at every point in space and time, then integrates over
a prediction grid to get a total. The building blocks:

- **Response** — the default benchmark uses swept-area density (`rho_biomass` in kg·nmi⁻², or
  `rho_abundance` in n·nmi⁻²). A valid alternative is raw catch weight/count with a log swept-area
  **offset** supplied through `sdmTMB(..., offset = ...)`; state the choice in the data report.
  `config.yaml` `EFFORT` selects it (`"density"` or `"offset"`); see *Effort and the index scale*
  below. In the installed sdmTMB API, an offset in a delta family applies to the positive
  component only. If sampled area should also affect occurrence probability, use a Poisson-link
  delta family (`delta_lognormal(type = "poisson-link")`), in which the offset enters both
  components, or Tweedie; see `model-selection.md` for when each is preferred, and for the
  Jacobian correction needed to compare density-response and offset candidates.
- **Fixed effects** — `~ 0 + geartype + s(month) + s(depth)`. The `0 +` drops the global
  intercept so each `geartype` level is estimated directly; `s()` are penalised smooths
  (mgcv-style) for seasonal and depth effects. **No temperature term by default.**
- **Spatial random field** `omega_s` — `spatial = "on"`. Time-invariant spatial structure.
- **Spatiotemporal field** `epsilon_st` — `spatiotemporal = "ar1"` (also `"iid"`, `"rw"`,
  `"off"`), with `time = "year"`. AR1 shares information across years; IID does not.
- **Family** — `delta_lognormal()` (a hurdle: binomial presence × lognormal positive
  density). Alternatives: `delta_gamma()`, `tweedie()`, and the Poisson-link variants
  `delta_lognormal(type = "poisson-link")` / `delta_gamma(type = "poisson-link")` with a
  swept-area offset. Tweedie with an offset is a valid baseline: its single linear predictor
  carries the offset into both the zero probability and the positive mean.
- **Time step** — `time = "year"` is the **index year**, which equals the calendar year unless
  `INDEX_YEAR_START_MONTH` says otherwise (a season spanning New Year, or an autumn survey
  combined with the following winter survey). `prepare_model_data()` builds it and keeps
  `calendar_year` beside it; see `data-filtering.md`.

## Effort and the index scale

One convention, whatever the family:

1. **Swept area once, in nmi²**: `swept_area_nmi2(distance_nmi, width_m)` =
   `distance × width / 1852`. Never combine a width in km with a km²→nmi² factor; that is
   wrong by a constant (≈0.54) and invisible in a relative index.
2. **Fit**: `EFFORT: "density"` → response `catch / swept_area`, no offset. `EFFORT: "offset"` →
   response `catch`, `offset = "log_swept_area"` passed as a **column name** (it stays aligned
   with the rows through `selection_frame()`, `update()` and subsampling).
3. **Predict at offset 0** — one unit of swept area — on the grid. The prediction is then a
   density per nmi² for both conventions. `predict_index()` does this explicitly; in sdmTMB
   ≥ 1.2.0, `predict()` on `newdata` also defaults to offset 0. Do not predict "catch per mean
   tow" and divide afterwards: forgetting the division by tow distance is the commonest error.
4. **Integrate with the grid cell area** in nmi² (`(GRID_KM / 1.852)^2`), taken from the grid
   constructor, never from polygon area ÷ point count.
5. **Check the scale** with `check_index_scale(..., fit = fit)`. The *unit ratio* — model
   density at the sampled hauls (offset 0) over observed density — does not depend on coverage;
   a median outside 1/1.5–1.5 points to a wrong swept-area unit or an offset on the wrong
   scale. The *design ratio* — index over mean observed density × grid area — is context:
   coverage differences move it legitimately, and only an order-of-magnitude departure suggests
   a misplaced cell area or tow-distance division. Neither check catches a constant error
   smaller than its tolerance, which is why points 1–4 are written once in the helpers.

## Catchability covariates

Covariates that change catch rate without changing abundance — time of day or sun altitude for
species that migrate vertically, a survey/season factor — enter the formula
(`CATCHABILITY_TERMS`, `SURVEY_EFFECT`) and are **predicted at a stated reference**
(`CATCHABILITY_REFERENCE`, `REFERENCE_SURVEY`): daylight, a mid-day hour, the most-sampled
survey. The reference sets the index level, not its shape. Use `sun_altitude` rather than
clock `hour` at high latitudes, where polar day and night decouple light from time; a cyclic
`s(hour, bs = "cc")` needs `knots = list(hour = c(0, 24))`. Treat them as fixed-effect
candidates in Step 3, not defaults.

## Coordinates — kilometres

sdmTMB expects projected `X`/`Y` in **kilometres**. Add them from lon/lat with:

```r
dt <- sdmTMB::add_utm_columns(dt, ll_names = c("lon", "lat"), utm_crs = 32633)  # X, Y in km
```

Keep the CRS (here EPSG:32633, UTM 33N) — you need it for the grid and maps. `sdmTMBexperiments`
helpers multiply `X`/`Y` by `coord_multiplier = 1000` to get CRS metres.

## Mesh

```r
mesh <- sdmTMB::make_mesh(dt, xy_cols = c("X", "Y"), cutoff = mesh_cutoff)  # cutoff in km
```

Smaller `cutoff` → more knots → finer resolution but slower. Typical values 50–100 km for
shelf-scale surveys. Optionally add a land barrier:

```r
mesh <- sdmTMBextra::add_barrier_mesh(mesh, land_polygon, proj_scaling = 1000)
```

Visualise with `sdmTMBexperiments::plot_mesh(mesh, crs = dt_crs, data = dt)`.

## Fit

```r
fit <- sdmTMB::sdmTMB(
  value ~ 0 + geartype + s(month) + s(depth),
  data           = dt,
  mesh           = mesh,
  family         = sdmTMB::delta_lognormal(),
  spatial        = "on",
  spatiotemporal = "ar1",
  time           = "year",
  control        = sdmTMB::sdmTMBcontrol(newton_loops = 2)
)

sdmTMB::sanity(fit)   # ALWAYS check convergence, SE gradients, PD Hessian, range vs domain
```

Report sanity results from the objects, not from memory: never hard-code "all models passed"
in a template. Place a generated sentence after the sanity table (the template's
`sanity_sentence()` in `R/report_helpers.R` gives the number passed and each failing model's
checks in plain words).

If `sanity()` flags problems (large gradients, non-positive-definite Hessian, range larger
than the domain), the index is not trustworthy — simplify (drop a smooth, coarsen the mesh,
change the spatiotemporal structure) rather than pressing on.

## Prediction grid and index

Predict to a regular grid covering the survey domain, replicated over years, with reference
values for the fixed effects; then integrate. Use the helpers for the grid:

```r
region <- sdmTMBexperiments::make_survey_prediction_region(dt, crs = dt_crs)
grid   <- sdmTMBexperiments::make_prediction_grid(region, resolution = grid_side_size,  # km
                                                  max_depth = 1400)
grid   <- tidyr::crossing(grid, year = sort(unique(dt$year)))
grid$geartype <- "Shrimp"; grid$month <- 8L   # reference levels
grid   <- add_reference_levels(grid, dt, cfg)  # survey and catchability references

index <- predict_index(fit, grid, area = grid_cell_area_nmi2, bias_correct = TRUE)
# index: year, est, lwr, upr, se, log_est, se (on the response scale after bias correction)
```

`predict_index()` (project `R/index_helpers.R`) predicts at offset 0 on the fitted years and
calls `get_index()`; with sdmTMB ≥ 1.2.0 it uses `get_index(fit, newdata = )`, since
`predict(return_tmb_object = TRUE)` is deprecated there.

- **`area`** scales cell density to cell total; use the grid cell area in the response's area
  unit (e.g. `(grid_side_size / 1.852)^2` nmi² for 10 km cells).
- **`bias_correct = TRUE`** for final indices (epsilon bias correction; slower). Leave `FALSE`
  while exploring.
- For **length-group** indices, fit/predict per group and combine; `get_index_split()`
  computes indices for many response columns efficiently — see `sdmtmbexperiments.md`.

## Diagnostics

- Randomised-quantile residuals + Q-Q (`sdmTMBexperiments::plot_residual_qq()`).
- `simulate(fit, nsim = ...)` for posterior-predictive checks.
- Predicted density maps and random-field maps
  (`plot_prediction_map()`, `plot_random_field()`).
- Cross-validation with `sdmTMB::sdmTMB_cv()` (wrapped by `sdmTMB_mesh_cv()`).

## Gotchas

- **X/Y must be km.** Passing metres puts data in the wrong place and breaks the mesh.
- **Keep true zeros** — the binomial part needs absences.
- **AR1 vs IID + year effect** — an index for SPiCT or another state-space assessment must not
  be temporally smoothed: use `spatiotemporal = "iid"` with `year` as a fixed effect, and no
  `s(year)` or `time_varying`. See `model-selection.md`, *The assessment constraint*. A year
  effect **with** an AR1 field is a third configuration (see `model-selection.md`).
- **A year factor must be a precomputed column** (`fyear`), never `factor(year)` in the
  formula. With `extra_time`, an inline factor gains levels for the missing years and the model
  is not identifiable (sdmTMB issue #320).
- **Trim the grid by depth after extracting depth per cell.** Matching cells to a bathymetry
  that was first filtered to a depth band by nearest neighbour gives out-of-band cells the
  band edge's depth instead of removing them. Extract per cell, then keep
  `MIN_DEPTH ≤ depth ≤ MAX_DEPTH`, and report cells outside the depth range of the data
  (`depth_extrapolation()`): the depth smooth extrapolates there.
- Bias correction and `simulate()` are slow; cache model outputs to `data/output` and toggle
  refits off on re-render (`rendering.md`).
- **Report the mesh's real vertex count**, read from the object (`mesh$mesh$n`), not the cutoff
  and not the number of knots you asked for — the SPDE construction adds vertices for the
  boundary and the extension beyond it.
- **A failing fit can be the mesh draw, not the model.** A pathological mesh makes the
  optimiser die with `NA/NaN gradient evaluation` within a minute while the *same* formula and
  data fit cleanly from a different mesh. Before simplifying the specification, try a different
  mesh (a different `cutoff`, or a different seed for a k-means mesh) — then keep the successful
  one fixed so the fit stays reproducible.
- **If `bias_correct = TRUE` runs out of memory** (`std::bad_alloc` in `MakeADHessObject2` — it
  builds an AD Hessian over every grid cell × year), first coarsen the prediction grid: it only
  has to resolve what the fitted field can represent, so a grid several times finer than the
  mesh adds cells without adding information. If it still will not fit, run without bias
  correction and **say so in the document**: the plug-in sum of `exp()` is biased low relative
  to the corrected estimator. That bias largely cancels in a *relative* index rescaled to its
  own mean, but the cancellation assumes the variance of the linear predictor is stable across
  years, and the intervals should be read as indicative rather than exact.
- **A survey that skipped a year needs `extra_time`.** With `spatiotemporal = "ar1"` or
  `"rw"`, sdmTMB warns "Detected irregular time spacing" and the fit can grind for a very long
  time or fail to resolve, because the AR1 process assumes evenly spaced steps. Pass the
  missing years — `sdmTMB(..., extra_time = c(2006, 2008))` — so the process has a step for
  each. Surveys skip years often enough that this is worth checking before every `ar1` fit:
  `setdiff(min(dt$year):max(dt$year), unique(dt$year))`.
- **Selection tables lie unless the candidates are comparable** — identical records, a common
  likelihood scale, hold-out likelihood per observation. See `model-selection.md`.
- **An integer `cutoff` silently wrecks the mesh.** `yaml` parses `MESH_CUTOFF_KM: 100` as
  `100L`, and `make_mesh()` given an integer cutoff builds one vertex per unique location
  (53 221 instead of 76 vertices for one 14 683-haul dataset; the only signal is the generic
  ">1000 vertices" warning, and the fit never finishes). Only `class()` shows the difference.
  The template's `R/0_setup.R` coerces measurement settings to double after reading the
  config; add any new numeric setting to that list.
- **Offsets in `sdmTMB_cv()`.** Pass the offset as a **column name** (`offset =
  "log_swept_area"`) so each fold subsets it; a vector is not subset. For a candidate without an
  offset, **omit** the argument: `sdmTMB_cv()` rejects an explicit `offset = NULL` ("Please use
  a character value for 'offset'") although `sdmTMB()` accepts it. `cv$converged` is a single
  logical (all folds converged), not a per-fold vector.
- **Degenerate terms — read which parameter collapsed.** Typical patterns in coastal survey
  data:
  - `s(month)` with very uneven seasonal coverage: smooth SD at 0 in both delta components,
    tiny eigenvalues, NaN SEs on every fixed effect and NaN index limits. A survey-series term
    usually already carries the season; drop the month smooth (`INCLUDE_MONTH: false`).
  - A spatial field with `sigma_O` near 0 and a huge `ln_tau_O` SE: switch it off for that
    component only (`SPATIAL: ["on", "off"]`).
  - An AR1 field with `rho` at 0.99–1.00 has absorbed the persistent spatial pattern; the
    matching spatial field then collapses. Test `"rw"` (and spatial off) against it.
  - Changing family moves the collapse: a field that was estimable under a standard delta can
    collapse in the other component under a Poisson-link delta. Re-run the random-field stage
    after any family change.
- **`predict()` and the Poisson-link offset.** sdmTMB applies the fitting offset to both
  Poisson-link components, but (sdmTMB 1.0.0.9011) a *prediction-time* offset is not applied to
  component 1, although the total stays correct. Harmless at `offset = 0`, the recommended
  prediction point; check before predicting at any other offset.
- **Combine delta components on the right link.** Use `est1 + est2` (log scale) for a
  Poisson-link first component and `plogis(est1) * exp(est2)` for a logit one
  (`delta_log_density()` in the template). Branch on `fit$family$link[1]`.
- **`plot_random_field()` errors on a field that is switched off** rather than skipping it;
  plot only the fields the fit has (`fitted_fields()` in the template).
- **`execute: warning: false` hides `warning()`.** In a long selection render, report candidate
  failures with `cat()`/`message()`, and make every results table emit its full column set
  even when a candidate crashed, so one failure cannot kill hours of fitting at the last chunk.
