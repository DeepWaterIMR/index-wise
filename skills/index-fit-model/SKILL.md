---
name: index-fit-model
description: Step 2 of the index workflow — fit the first feasible sdmTMB model (no length groups) to confirm the method works, build the prediction grid, and compute a survey index. Use after the data are compiled (step 1) and the user is ready to model. For sdmTMB index work outside a scaffolded index-wise project, use index-sdmtmb.
---

<!-- pack-resources:start -->
**Pack resources:** the `index-wise` root is `~/.index-wise/config.json` → `index_template_path`, else `~/.fiskwise/config.json` →
`components.index-wise.path`, else the checkout containing this skill. Paths such as `knowledge/`
and `project-template/` are relative to that root, never `../../` from a skills folder; resolve
links that leave this skill's folder against the source skill there. Use absolute paths.
<!-- pack-resources:end -->


# Step 2 — Fit the first feasible model

Goal: get a single, working total-biomass (or abundance) index. **Start simple — no length
groups, no temperature** — to confirm the method works before adding complexity. (For
background material, see the lookup table in `knowledge/workflow.md`.)

Read `knowledge/sdmtmb.md` and `knowledge/sdmtmbexperiments.md` first, and skim the sdmTMB docs
(<https://pbs-assess.github.io/sdmTMB/>). **Attach `library(sdmTMBexperiments)`.**

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Work in `docs/sdmtmb/fit/fit.qmd`

1. **Load** the compiled dataset from `data/output/` and build the modelling frame with
   `prepare_model_data(dt, cfg)`: response from `RESPONSE` and `EFFORT` (density, or catch
   with the `log_swept_area` offset column), `year` = **index year**, `calendar_year` kept.
   Keep true zeros.
2. **Coordinates** — `prepare_model_data()` adds `X`, `Y` in **km**
   (`sdmTMB::add_utm_columns(..., utm_crs = <CRS>)`).
3. **Mesh** — `make_mesh(dt, c("X","Y"), cutoff = <MESH_CUTOFF_KM>)`; visualise with
   `plot_mesh()`. Barrier mesh only if `BARRIER: true`.
4. **Fit** the default model:

   ```r
   fit <- sdmTMB::sdmTMB(
     value ~ 0 + geartype + s(month) + s(depth),   # no temperature by default
     data = dt, mesh = mesh,
     family = sdmTMB::delta_lognormal(),
     spatial = "on", spatiotemporal = "ar1", time = "year",
     control = sdmTMB::sdmTMBcontrol(newton_loops = 2)
   )
   sdmTMB::sanity(fit)
   ```

   Keep `geartype` in the formula when multiple major gears are present (always, if a single
   set gear width was used — see the gear-width note in `config.yaml`). Pass
   `offset = model_offset` (NULL for density). `SURVEY_EFFECT` and `CATCHABILITY_TERMS`
   add configured terms through `build_formula()`; `YEAR_EFFECT: true` adds the precomputed year
   factor `fyear` (SPiCT-type base: IID fields + year effect; a delta model then needs a positive
   haul in every year — fit a fishable-length product without years that have none). Restrict
   the model data to the stock prediction region first (`restrict_to_region(dt,
   read_prediction_region(cfg))`), and drop stations without depth. If `sanity()` fails, simplify (coarser mesh,
   drop a smooth, change spatiotemporal) rather than forcing it.
5. **Prediction grid** — the stock region from `read_prediction_region(cfg)` (built in
   `<stock>-3-data.qmd`; `make_survey_prediction_region()` only when there is none) →
   `make_prediction_grid()` (GEBCO depth per cell), trim to `MIN_DEPTH`–`MAX_DEPTH`, replicate
   over index years, set the reference gear and month (`reference_gear()`, `reference_month()`:
   config, else the most sampled level), then `add_reference_levels()` for the survey and catchability terms.
   Report cells outside the data's depth range (`depth_extrapolation()`).
6. **Predict & index** — `predict_index(fit, grid_for_fit(grid, fit), area = <cell area in nmi²>)`: offset 0, so
   predictions are densities per nmi² under either `EFFORT`. Leave `bias_correct = FALSE` while
   exploring. Then run `check_index_scale(..., fit = fit)`: a median unit ratio (model vs
   observed density at the hauls) outside 1/1.5–1.5 means a unit error to find before Step 3;
   the design ratio against an unstratified swept-area estimate is context
   (`knowledge/sdmtmb.md` *Effort and the index scale*).
7. **Diagnostics** — `plot_residual_qq()`, `plot_prediction_map()`, `plot_random_field()`,
   `plot_fixed_effects()`.
8. **Save** the fit, grid, predictions, and index to `data/output/` (toggle-controlled).

## Toggles & rendering

Expose `refit_model`, `recompute_grid`, `bias_correct` params (see `knowledge/rendering.md`).
**Code-review the chunks before rendering**, then render via `index-render` in a screen session
with a log. After the first successful render, flip `refit_model`/`recompute_grid` to `FALSE`.

## Next

If the simple model works and looks sane, proceed to Step 3 — validation
(`index-validate-model`). Record the mesh/formula/family choices in project memory.
