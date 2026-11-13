---
name: index-cpue-model
description: Standardise commercial CPUE into a relative abundance index with glmmTMB (GLMM), mgcv (GAMM) or sdmTMB (spatio-temporal GLMM) — effort as offset or covariate, vessel and year-level random effects, reference conditions, area-weighted prediction over the fished domain, AIC selection on the catch scale, grouped residual dispersion, vessel bootstrap, retrospective and final-month sensitivity, and export for the assessment. Use after the CPUE records are prepared (index-cpue-data).
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


# CPUE step 2 — standardisation and index

Goal: a standardised CPUE index with honest uncertainty and a statement of what it represents.
**Read `knowledge/cpue-models.md` first**, then `knowledge/model-selection.md` (comparability
rules) and, for sdmTMB, `knowledge/sdmtmb.md`. `examples/snowcrab-ers-cpue/` runs all three
engines on synthetic data with a known trend; run it once to see what each engine recovers.

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Choose the engine (`CPUE: engine` in `config.yaml`)

- **glmmTMB** — many records, crossed random effects (vessel, area, vessel-year, area-year),
  space only as area factors. The year effect weights areas by where fishing happened.
- **mgcv** — smooths of anything, a spatial and a space-time smooth, area-weighted index from
  coefficient draws (`cpue_gam_area_index()`).
- **sdmTMB** — spatial and spatio-temporal random fields; the index integrated over the fished
  domain (`cpue_sdm_index()`). The default when positions are reliable and the fished area or
  the stock distribution shifts.

Fitting more than one engine on the same records is a useful check: where they disagree, the
spatial weighting is doing the work.

## Work in `docs/sdmtmb/cpue/cpue.qmd` (model sections)

1. **Response and family** — positive catch, `Gamma(link = "log")` by default; effort as a
   covariate (`CPUE: effort_treatment: covariate`), reporting the slope; an offset only if the
   slope is close to 1. Compare responses with `cpue_aic_catch_scale()`.
2. **Formula** — `0 + fyear`, effort, season and depth smooths, a vessel random intercept.
   Precomputed factor columns for every grouping (`vessel_year`, `area_year`); no covariates
   that trend with time by construction.
3. **Reference conditions** (`CPUE: reference`) — standard effort, season day, mean covariates,
   population level.
4. **Prediction domain** — the fished domain (convex hull of the records, trimmed to their depth
   range) or a core area; never cells the fleet does not fish.
5. **Selection** (`run_selection`) — drop-one fixed effects on identical records, then random
   effects, then (sdmTMB) `spatiotemporal` among fits that pass `sanity()`; show the index of
   each candidate.
6. **Diagnostics** — `sanity()` (sdmTMB) and grouped residual dispersion
   (`cpue_pearson_groups()` for any engine; `cpue_dharma_groups()` for glmmTMB): vessel,
   vessel-year, area-year. Dispersion > 1 for vessel-year → add `(1 | vessel_year)` or rely on
   the bootstrap.
7. **Uncertainty** (`run_bootstrap`) — `cpue_vessel_bootstrap()`, stratified by main area when
   areas differ; report model and bootstrap intervals side by side.
8. **Sensitivity** (`run_sensitivity`) — retrospective and forward peels, the final-month cut,
   each filter threshold, core area vs hull, and any data-source break (source effect vs two
   series).
9. **Export** — `build_assessment_index_handoff()` with the relative index, log-scale `se`, the
   fishery's mid-season as timing, and the fleet/area it represents; separate series across
   breaks that need their own catchability.

## Toggles & rendering

Selection, bootstrap and sensitivity refit the model many times; keep them behind their params,
cache fits to `data/output/cpue/`, **code-review first**, and render with `index-render` in a
screen session with a log; suggest a server for the bootstrap.

## Output

The CPUE index, its diagnostics and sensitivity, and a short decision note in `ai/memory/`:
engine, formula, family, effort treatment, domain, filters, and the uncertainty the assessment
should use.
