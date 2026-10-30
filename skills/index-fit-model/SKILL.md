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

## Work in `docs/data-report/fit/fit.qmd`

1. **Load** the compiled dataset from `data/output/`. Set the response
   (`value = rho_biomass` or `rho_abundance` from `config.yaml`). Keep true zeros.
2. **Coordinates** — `sdmTMB::add_utm_columns(..., utm_crs = <CRS>)` → `X`, `Y` in **km**.
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
   set gear width was used — see the gear-width note in `config.yaml`). If `sanity()` fails,
   simplify (coarser mesh, drop a smooth, change spatiotemporal) rather than forcing it.
5. **Prediction grid** — `make_survey_prediction_region()` → `make_prediction_grid()` (GEBCO
   depth), replicate over years, set reference `geartype`/`month`.
6. **Predict & index** — `predict(fit, newdata = grid, return_tmb_object = TRUE)` →
   `sdmTMB::get_index(..., area = <cell area in nmi²>)`. Leave `bias_correct = FALSE` while
   exploring.
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
