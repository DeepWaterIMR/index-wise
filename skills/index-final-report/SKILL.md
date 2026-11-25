---
name: index-final-report
description: Step 4 of the index workflow — build the self-contained final model report (multiple indices, diagnostics, regional, retrospective, survey-comparison and influence sections) and export the selected index for assessment. Use after the model is validated (step 3). Modelled on ref-assessment-index/benchmark/beaked. For sdmTMB index work outside a scaffolded index-wise project, use index-sdmtmb.
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
   - Size-, sex- or maturity-class indices, as separate fits or one stacked class model
     (`knowledge/model-selection.md` *Stacked class models*; state whether the classes share
     their spatial fields).
   - The **assessment-selected index** — `iid` + `year` as a fixed effect when it feeds SPiCT
     or another state-space model, so the series is not smoothed twice
     (`knowledge/model-selection.md`). Use `get_index_split()` to compute many indices
     efficiently.
   Compute every index with `predict_index()` (offset 0, fitted years, cell area), so all
   products share the effort convention.
2. **Results** — fixed-effect estimates/tables (`plot_fixed_effects()`), predicted density maps
   (`plot_prediction_map()`), random fields, residual Q-Q, variance partitioning, and
   simulation-based diagnostics.
3. **Bias correction** — `bias_correct = TRUE` for the final index runs (slow; behind a
   toggle).
4. **Export** the selected index as the versioned `assessment-index.rds` hand-off
   (`knowledge/assessment-index-handoff.md`); spict-wise and gadget-wise read it directly.

## Report structure and computation

The report follows the beaked-redfish benchmark document and must stand on its own for a
reviewer: Introduction (products, assessment use, pointers to the data and validate
documents), Material and methods (data overview with a table by survey series, hauls per year
and an annual density bubble map; model structure with the linear predictor written out;
mesh; model fitting; prediction-grid depth map; index computation; sensitivity analyses),
Results (sanity table, residual Q-Q, simulated vs observed zero share and mean density,
density histograms, fixed- and random-effect tables, conditional effects, variance
partitioning, spatial and spatiotemporal field maps, mean and annual density maps), Survey
indices (absolute, mean-scaled and CV panels), the sensitivity sections, exported indices,
and index tables in the appendix. Data selection and model selection are summarised and
linked, not repeated: mesh, barrier, anisotropy and mesh-CV comparisons belong in
`validate.qmd`.

All slow work runs on a server through `R/report/run_report.sh`, which runs
`R/report/report_compute.R` step by step (grid, fit and post per product, then retro,
surveys, loso, influence) and caches each result under `<OUTPUT_DIR>/report/`; the document
only reads the caches, so it renders in minutes and a failed step reruns alone.

Sensitivity sections (`*-section.qmd`, included from `report.qmd`):

- `region-section.qmd` — regional contributions: the index summed by ICES division
  (`index_by_region()`), with hauls per division.
- `retro-section.qmd` — retrospective peels of the assessment candidates with Mohn's rho.
  Use `run_report_retro()`, not `sdmTMB_retro()`, for models with a year factor (see
  `knowledge/sdmtmbexperiments.md`). Peels and leave-out refits drop the hauls of month levels
  left without a positive catch (`drop_empty_levels()`); otherwise that coefficient is
  unidentified, the Hessian is not positive definite and every peel fails the sanity checks.
- `survey-comparison-section.qmd` — single-survey indices (`compare_surveys()`; each survey
  model has the compiled IID specification with a year factor and no month term, so it could
  serve as an alternative index; years without catches are dropped; a model that fails is
  simplified by `survey_model_ladder()`: no spatiotemporal field, then Tweedie) and
  leave-one-survey-out refits (`sdmTMB_leave_out(id_col = "cruiseseries")`). Report which
  sanity checks the survey models fail.
- `influence-section.qmd` — cruises and hauls screened with `density_share()`, then left out
  one at a time; flag influence ≥ 0.1 with leverage ≥ 2 (`knowledge/influence-diagnostics.md`).
- `bridging-section.qmd`, `robustness-section.qmd` — optional, behind params.

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
  year. State which survey indices follow the compiled index from those correlations, survey by
  survey; do not group a coastal or fjord survey with the shelf surveys. If the dropped series
  is the prediction reference, move the reference to the series with most positive hauls and
  say so.
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
cache every product to `data/output/` so re-renders load. Keep the HTML small: per-chunk
`dev: jpeg` on map chunks, png for line plots, sensible dpi (`knowledge/rendering.md` §4).

## Output

The final report and the exported assessment index. Record the selected index and export path
in project memory.
