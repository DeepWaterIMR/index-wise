---
name: cpue-lessons
description: Design decisions behind the commercial CPUE layer (knowledge, skills, template document, helpers, example) and the practices it was distilled from.
metadata:
  type: decision
  author: claude
  created: 2026-10-26
---

# The commercial CPUE layer

Added 2026-10-26 at the user's request, from the CPUE work of IMR crustacean assessment
projects (snow crab and red king crab trap fisheries, northern shrimp trawl fisheries). Only
methods were taken over; no data, vessels, positions or project paths.

**Layout.** Background in `knowledge/cpue.md` (data sources, why CPUE is not abundance, record
preparation); models in `knowledge/cpue-models.md` (glmmTMB, mgcv, sdmTMB, prediction domain,
uncertainty, sensitivity, handoff). Two skills: `index-cpue-data` (records) and
`index-cpue-model` (standardisation). One template document `docs/data-report/cpue/cpue.qmd`
driven by the `CPUE:` block of `config.yaml`, with project-side helpers in
`R/cpue_helpers.R`. The CPUE document is optional: `docs/render.R` renders it in `all` only when
the logbook extract exists. Worked example: `examples/snowcrab-ers-cpue/` (synthetic data with a
known trend; tested in `config/test-cpue-helpers.R` for the helpers).

**Practices the projects converged on, now the defaults:**

- Positive catch per record, Gamma with log link; effort as a covariate with its slope
  reported, an offset only when the slope is ≈ 1; AIC compared on the catch scale (Jacobian).
- Vessel random intercept; replaced vessels split by a length (or power) change; core-fleet
  filters (years active, records) as configurable thresholds, each a sensitivity run.
- Population-level prediction at stated reference conditions; grouping factors as precomputed
  columns (an in-formula interaction turns `NA` into a new level and inflates intervals).
- Within-year correlation: grouped DHARMa dispersion, `(1 | vessel_year)` / `(1 | area_year)`,
  vessel bootstrap stratified by main area. Model SEs are usually too narrow.
- Spatial models predict over the **fished domain** only (hull or core area), never unfished
  cells; survey-density weighting is a sensitivity.
- Final-month retrospective for the incomplete terminal year; retrospective and forward peels.
- Data-source breaks (aggregated logbooks → ERS): source effect on overlap, two series with
  separate catchabilities, or the new source aggregated to the old unit — and check whether the
  "overlap" records are independent.

**Kept out on purpose:** commercial-data access and reading code. The user asked (2026-10-26)
that the background state explicitly that commercial data vary by source, country, period and
fishery and need bespoke treatment in each case; `knowledge/cpue.md` has that section, and the
skill and `cpue.qmd` point to it. Do not add a generic reader. Also kept out:
covariates that trend with time by construction (experience) as defaults; selection by AIC alone
across different response scales.

**Example result (one synthetic realisation):** spatial engines tracked the true trend closely,
while the non-spatial GLMM did worse than nominal CPUE, because its year effect weights areas by
where the fleet fished when the stock distribution shifts. That is the point the example
teaches; do not overstate it as a general ranking.

Related: [[reference-sources]], [[architecture]], [[conventions]].
