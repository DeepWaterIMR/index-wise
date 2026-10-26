---
name: index-final-report
description: Step 4 of the index workflow — build the final model report with extensions (multiple indices, length groups, and optional mesh/barrier/retro/CV/survey-comparison sections) and export the selected index for assessment. Use after the model is validated (step 3). Modelled on ref-assessment-index/benchmark/beaked.
---

<!-- pack-resources:start -->
**Pack resources:** resolve `index-wise` from `~/.index-wise/config.json` → `index_template_path` (or
`~/.fiskwise/config.json` → `components.index-wise.path`). If neither exists, use the
checkout containing this skill, or locate/obtain the pack through its install instructions.
Paths such as `knowledge/`, `cookbook/`, `config/` and `project-template/` belong to that
repository, not the current research directory. For a copied skill, resolve a link that
leaves this skill's directory against the corresponding source skill under that root;
keep bundled `references/` links relative to the skill. Never assume `../../` from an
agent's global skills folder reaches the repository. Use absolute resolved script paths.
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
   - The **assessment-selected index** — often `iid` + `year` as a fixed effect (confirm with
     the user). Use `get_index_split()` to compute many indices efficiently.
   Compute every index with `predict_index()` (offset 0, fitted years, cell area), so all
   products share the effort convention.
2. **Results** — fixed-effect estimates/tables (`plot_fixed_effects()`), predicted density maps
   (`plot_prediction_map()`), random fields, residual Q-Q, variance partitioning, and
   simulation-based diagnostics.
3. **Bias correction** — `bias_correct = TRUE` for the final index runs (slow; behind a
   toggle).
4. **Export** the selected index (`year, est, lwr, upr, se`) to `data/output/` in the shape the
   assessment consumes (e.g. an `.rds` for a SPiCT project).

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
- `bridging-section.qmd` — the new index against the previous assessment's published index
  (`PREVIOUS_INDEX_FILE`, in index years), both rescaled to their overlap mean; years beyond
  `REVISION_TOLERANCE` are flagged and each needs an explanation.
- `robustness-section.qmd` — whole-station subsampling, start-year peels, the terminal year
  without `LATE_COMPONENTS`, and down-weighted years (`ROBUSTNESS`). Diagnostics only; a
  barrier mesh is not rebuilt in these refits.

## Rendering

This is the heaviest document (many indices × length groups × bias correction). **Code-review
first**, render via `index-render` in a screen session with a log, **suggest a server**, and
cache every product to `data/output/` so re-renders load. Keep the HTML small: `fig-format:
jpeg`, sensible dpi.

## Output

The final report and the exported assessment index. Record the selected index and export path
in project memory.
