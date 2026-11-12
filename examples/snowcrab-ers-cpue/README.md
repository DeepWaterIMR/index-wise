# Worked example — a snow crab ERS CPUE index (simplified, synthetic)

A compact version of a trap-fishery logbook (ERS) CPUE index of the snow crab type, run on
**simulated** data so that each engine's index can be compared with a known abundance trend.
No real logbook records, vessels or positions are used; the coordinates are kilometres on an
arbitrary synthetic shelf.

```bash
Rscript examples/snowcrab-ers-cpue/snowcrab_ers_cpue.R
```

Run it from the index-wise root. It needs `dplyr`, `glmmTMB`, `mgcv` and `sdmTMB` (DHARMa
optional) and takes about a minute. It uses the project helpers in
`project-template/R/cpue_helpers.R`, the same ones a scaffolded project's `cpue.qmd` uses.

## What it simulates

| Element | Simulation | Why it matters |
|---|---|---|
| Stock | 2015–2025, rise and decline; one fixed and one aggregation moving north-east | the stock distribution shifts |
| Fishing ground | hauls only where x < 170 km; cells chosen with probability ∝ density^0.7 | preferential fishing (hyperstability) and an unfished part of the shelf |
| Fleet | 30 vessels, half entering later with 1.4× catchability, five with few records | fleet composition change; the core-fleet filter |
| Catch | Gamma, mean ∝ density × traps^0.8 × saturating soak × declining season | effort is not proportional; season and soak matter |
| Errors | 20 records with catch × 1000 | unit errors; the catch-range filter |

## What it fits

The structure of the snow crab ERS model: positive catch, Gamma with log link, `0 + fyear`, effort
(traps) as a covariate, smooths of soak time, season day and depth, a vessel random intercept,
the core-fleet filter (≥ 3 years, ≥ 100 records) and plausible ranges (100–400 traps, soak time
< 21 days, catch 10–5000 kg).

1. **glmmTMB** GLMM with splines and `(1 | vessel_id)`: index = year effect at reference
   conditions (`cpue_year_index()`).
2. **mgcv** GAMM with a spatial smooth, a space-year interaction and a vessel `re` smooth: index
   area-weighted over the fished domain, intervals from coefficient draws
   (`cpue_gam_area_index()`).
3. **sdmTMB** with spatial and IID spatio-temporal fields and the vessel random intercept: index
   integrated over the fished domain (`cpue_sdm_index()`).

The prediction grid is the convex hull of the selected hauls, so neither spatial engine predicts
the unfished part of the shelf. The truth is the total abundance over the same cells.

## What it shows (one realisation; seed 2015)

- The filter log: the catch-range step removes most of the "catch" with few records — those are
  the injected unit errors.
- The glmmTMB effort slope is about 0.8 (the simulated value), so an offset (slope 1) would be
  wrong.
- The spatial engines track the true trend closely (mean absolute log error ≈ 0.01). The
  non-spatial GLMM does **worse than nominal CPUE** here, because its year effect weights areas
  by where the fleet fished while the aggregation moved. Standardising for vessels alone does not
  correct for where the fleet fishes.
- Grouped residual dispersion of the GLMM by vessel-year.

Treat these as an illustration of mechanisms, not as a general ranking of engines: change the
seed, the fleet behaviour or the stock shift, and the gaps change. See `knowledge/cpue.md` and
`knowledge/cpue-models.md` for the reasoning, and the `index-cpue-data` / `index-cpue-model`
skills for the workflow on real data.
