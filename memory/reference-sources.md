---
name: reference-sources
description: The projects index-template's content is adapted from, and what each supplied.
metadata:
  type: reference
  author: claude
  created: 2026-07-02
---

# Reference sources

Content was **adapted** (not copied; data/paths stripped) from:

- **ref-index-paper** (public showcase, Vihtakari et al. 2026). Supplied the data-filtering
  logic (`docs/data/{Redfish bottom trawl, BioticExplorer_database, Compile_all_data}.Rmd`)
  and the Step 1–3 blueprint (`docs/SI files/SI-Text-{1,2,3}`). Critical filters:
  `gearcondition %in% 1:2`; `samplequality == 1` except coastal series `cruiseseriescode ==
  "23"` → `1:2`; drop `stationtype` C/2/A/E (superseded 2026-11 by the keep-list missing/1/3/9/13 from the redfish benchmark); `distance` 0.3–5 nmi; duplicate removal;
  swept-area density with gear-specific 25 m / ~94 m widths in the historical redfish example;
  the current template default is a common 25 m width with `geartype` as a fixed effect.
- **ref-assessment-index** `docs/benchmark/beaked/`. Step-4 final report + `*-section.qmd`
  includes (mesh/barrier/retro/cv/survey-comparison); multiple indices (total, over-30 cm,
  length groups); selected index `Over 30 cm biomass` (iid + year effect) vs total (ar1).
  Also had `memory/index_template_plan.md` sketching this template.
  From `SI-Text-3-model-selection.qmd` specifically: the staged selection sequence (component
  ranking → drop-one fixed effects → family → spatiotemporal structure), `Crashed`/`Converged`/
  `Sanity` as first-class table columns with a status-coded dot plot, ΔNLL alongside ΔAIC, and
  plotting the resulting **index for every candidate at every stage**.
- **sdmTMBexperiments** — the helper package all comparisons/grids/maps call. Coords in km,
  `coord_multiplier = 1000`; attach the package for ggOceanMaps land data.
- **A commercial-CPUE (ERS logbook) sdmTMB index project** for the same institute. Supplied
  the model-selection *discipline* now in `knowledge/model-selection.md`, none of its
  commercial-fishery specifics: identical records for every candidate (one complete-case
  selection frame, full data for the final fit); a `spec` column stating what each row fitted;
  hold-out log-likelihood **per observation** with `Folds used` / `pd Hessian` /
  `Comparable` columns; AIC ladder first and cross-validation on an AIC-ranked shortlist;
  per-candidate resumable caches with an env-var fan-out across R processes; reporting the AIC
  gap when the carried-forward model is not the winner; and looking values up by label rather
  than row position in a rendered document.
- **spict-template** — the scaffold/AGENTS/memory conventions mirrored here.
- **BAIT** — the knowledge-pack + global-skills model, and the data-access layer.

**User refinements to the paper defaults:** Russian data INCLUDED by default; NO temperature
term by default; use a common 25 m gear width with `geartype` as a fixed effect unless a project
documents a reason to revert to gear-specific widths; code-review before every slow render.

Related: [[architecture]].
