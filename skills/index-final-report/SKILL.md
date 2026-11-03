---
name: index-final-report
description: Step 4 of the index workflow — build the final model report with extensions (multiple indices, length groups, and optional mesh/barrier/retro/CV/survey-comparison sections) and export the selected index for assessment. Use after the model is validated (step 3). Modelled on ref-assessment-index/benchmark/beaked. For sdmTMB index work outside a scaffolded index-wise project, use index-sdmtmb.
---

<!-- pack-resources:start -->
**Pack resources:** the `index-wise` root is `~/.index-wise/config.json` → `index_template_path`, else `~/.fiskwise/config.json` →
`components.index-wise.path`, else the checkout containing this skill. Paths such as `knowledge/`
and `project-template/` are relative to that root, never `../../` from a skills folder; resolve
links that leave this skill's folder against the source skill there. Use absolute paths.
<!-- pack-resources:end -->


# Step 4 — Final report + extensions

Goal: extend the validated model to the full set of assessment products, write the final
report, and export the selected index. Modelled on
`ref-assessment-index/docs/benchmark/beaked/` (the `reb-assessment-survey-indices.qmd` document
and its `*-section.qmd` includes).

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Work in `docs/<slug>/report.qmd`

1. **Multiple indices** — fit/predict the products the assessment needs:
   - Total biomass (`spatiotemporal = "ar1"`, no year effect).
   - Over-X-cm biomass (threshold from `config.yaml`).
   - Length-group abundance indices (breaks from `config.yaml`).
   - The **assessment-selected index** — `iid` + `year` as a fixed effect when it feeds SPiCT
     or another state-space model, so the series is not smoothed twice
     (`knowledge/model-selection.md`). Use `get_index_split()` to compute many indices
     efficiently.
2. **Results** — fixed-effect estimates/tables (`plot_fixed_effects()`), predicted density maps
   (`plot_prediction_map()`), random fields, residual Q-Q, variance partitioning, and
   simulation-based diagnostics.
3. **Bias correction** — `bias_correct = TRUE` for the final index runs (slow; behind a
   toggle).
4. **Export** the selected index as the versioned `assessment-index.rds` hand-off
   (`knowledge/assessment-index-handoff.md`); spict-wise and gadget-wise read it directly.

## Optional include sections

Each is a `*-section.qmd` included from `report.qmd`, switched by a YAML param plus a compute
toggle (default off), mirroring the benchmark:

- `mesh-section.qmd` — mesh comparison (`compare_meshes`).
- `barrier-section.qmd` — barrier-mesh comparison.
- `retro-section.qmd` — retrospective (`sdmTMB_retro`, `mohns_rho`).
- `cross-validation-section.qmd` — mesh CV (`sdmTMB_mesh_cv`).
- `survey-comparison-section.qmd` — per-survey indices vs the compiled index
  (`compare_surveys`): filter to one `cruiseseries`, build a survey-specific mesh and grid,
  compute the index, compare (`plot(type = "index"|"scatter"|"spatial")`).

## Annual update mode

Once the specification is selected, the report is re-run every year for the assessment. Keep
it an update report, not a repeat of model selection (that stays in `validate.qmd` and the
benchmark documentation):

- **Fit the final model from `config.yaml`** through one function used by every product, and
  inject the settings into the `sdmTMB()` call as values (`rlang::inject(sdmTMB::sdmTMB(...,
  family = !!model_family, ...))`), so `fit$call` can be re-evaluated by `sdmTMB_retro()` and
  refit helpers in a fresh environment.
- **Archive each year's inputs and outputs**: the compiled roster as
  `data/output/archive/compiled-data-<last complete year>.rds` and the exported index as
  `archive/index-<year>.csv`. Next year compares against the latest earlier archive, which
  separates changes from new data from changes in the database's back catalogue.
- **Survey signal**: refit the selected product leaving out one survey series at a time, and fit
  the major series alone over their own footprint (start year: first with enough hauls).
  Compare mean-scaled indices by correlation, mean absolute relative difference and the terminal
  year. If the dropped series is the prediction reference, move the reference to the series
  with most positive hauls and say so.
- **Previous index**: compare with the index the assessment last read, by shape on a common
  scale; keep its source path in config.
- **Record failed refits, do not stop.** A leave-one-out or single-series fit that does not
  converge becomes a row with a reason, so one failure cannot kill a long server render.
- **Check convergence per product.** A specification that passes for total biomass can fail for
  a sparse size product (AR1 `rho` at 1, a smooth SD at 0, non-PD Hessian); the products'
  diagnostics and the survey-signal results inherit that failure and are provisional until it
  is fixed.
- Run a first round with `bias_correct: false`, then the final run with bias correction.
- A `dev_mode` parameter (a fraction of hauls, a coarse mesh, no archive or export) smoke-tests
  the document before a server run.

## Rendering

This is the heaviest document (many indices × length groups × bias correction). **Code-review
first**, render via `index-render` in a screen session with a log, **suggest a server**, and
cache every product to `data/output/` so re-renders load. Keep the HTML small: `fig-format:
jpeg`, sensible dpi.

## Output

The final report and the exported assessment index. Record the selected index and export path
in project memory.
