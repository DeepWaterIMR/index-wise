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
  In the installed sdmTMB API, an offset in a delta family applies to the positive component only.
  If sampled area should also affect occurrence probability, use a Poisson-link delta family
  (`delta_lognormal(type = "poisson-link")`), in which the offset enters both components; see
  `model-selection.md` for why it is preferred when it fits and converges, and for the Jacobian
  correction needed to compare density-response and offset candidates.
- **Fixed effects** — `~ 0 + geartype + s(month) + s(depth)`. The `0 +` drops the global
  intercept so each `geartype` level is estimated directly; `s()` are penalised smooths
  (mgcv-style) for seasonal and depth effects. **No temperature term by default.**
- **Spatial random field** `omega_s` — `spatial = "on"`. Time-invariant spatial structure.
- **Spatiotemporal field** `epsilon_st` — `spatiotemporal = "ar1"` (also `"iid"`, `"rw"`,
  `"off"`), with `time = "year"`. AR1 shares information across years; IID does not.
- **Family** — `delta_lognormal()` (a hurdle: binomial presence × lognormal positive
  density). Alternatives: `delta_gamma()`, `tweedie()`, and the Poisson-link variants
  `delta_lognormal(type = "poisson-link")` / `delta_gamma(type = "poisson-link")` with a
  swept-area offset.

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

pred  <- predict(fit, newdata = grid, return_tmb_object = TRUE)
index <- sdmTMB::get_index(pred, bias_correct = TRUE, area = grid_cell_area_nmi2)
# index: year, est, lwr, upr, se, log_est, se (on the response scale after bias correction)
```

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
  `s(year)` or `time_varying`. See `model-selection.md`, *The assessment constraint*.
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
