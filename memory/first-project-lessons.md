---
name: first-project-lessons
description: Reusable lessons consolidated after the first Atlantic halibut index-template project.
metadata:
  type: decision
  author: project team
  created: 2026-08-06
---

# Lessons from the first Atlantic halibut project

The generated Step 1 documents have two distinct roles. `compile-data.qmd` selects qualifying
surveys and documents coverage, catch, gear, timing, filters, and the filtering-script appendix.
`<species>-<region>-data-report.qmd` (now `docs/data/<stock>-3-data.qmd`; `compile-data.qmd` is now `<stock>-2-survey-selection.qmd`) documents the compiled station/response data, effort,
length products, and diagnostics. Keep length allocation and length-completeness material out of
survey selection.

Use survey-level qualification: a survey is one cruise and qualifies when at least one positive
target catch passes the standard haul filters and the exact region test. A cruise series groups
surveys in a time series; do not backfill failed surveys merely because another survey in that
series qualifies. Uncoded surveys are assessed individually before assigning `Other`.

The inherited sample-quality predicate is SQL-compatible and NA-safe:

```r
dplyr::if_else(
  !is.na(.data$cruiseseriescode) & .data$cruiseseriescode == "23",
  .data$samplequality %in% 1:2,
  .data$samplequality %in% 1
)
```

Apply it in the lazy query and retain the same check after collection. If code 23 represents a
coastal acoustic survey that targeted another species, document why the target species is assumed
to remain randomly sampled before retaining quality 2. Code 2 denotes targeted sampling rather
than generic “acceptable quality.” Likewise, retaining `gearcondition` code 2 can be appropriate
for a documented survey workflow but is not a universal ordered-code rule.

Use `missionid + serialnumber` as the BES fishstation key. For native NMD Biotic, use
`missiontype + startyear + platform + missionnumber + serialnumber`; `missionid` is added by
BioticExplorerServer. Do not build keys from cruise or vessel labels. A `stnall` row is a
catchsample, not necessarily a haul. Resolve multiple catchparts from identifiers, product and
raising fields, and comments before summing. Rare multisampler workflows can use separate
serialnumbers for bags and a shared `station` for the physical haul; require survey-specific
evidence before aggregating that way.

Raise length or individual observations within catchsample using the numeric representation
factor `catchcount / lengthsamplecount`. Keep the measured sample size separate, avoid rounding
and row expansion when weights are supported, and never average catch or swept-area densities
across unequal-effort rows: sum numerators and denominators before division.

For prediction-region overview maps, calculate observation and polygon extents in a display CRS
(default EPSG:3995), convert bounding boxes to corner points, and pass them to `basemap(data=...)`.
Use `bathy.style = "rbg"`, `ggnewscale::new_scale_fill()` before manual polygon fills,
`expand.factor = 1.1`, and `coord_sf(expand = FALSE)`. For station-position figures where zero
hauls must remain visible, omit bathymetry and use a light grey zero layer.

The template documents use a `VERSION` date label, an index-template provenance paragraph, and
project-specific author affiliations near the top. All figures and tables have explicit captions
and stable Quarto cross-reference labels. Generated outputs belong under root-level
`data/output/`; never create document-local output folders or track raw Biotic data/private paths.

When acquisition and modelling use different polygons, support this explicitly in configuration:
`ACQUISITION_REGION`/`ACQUISITION_REGION_LAYER` controls survey qualification, while `REGION`
remains the model-domain label. With `ADD_REGION_IDENTIFIER: true`,
`PARTITION_REGION`/`PARTITION_REGION_LAYER` adds a `region` column after exact spatial filtering,
so the full acquisition dataset can be compiled once and filtered during fitting. If multiple
regional datasets share a project, use root-level subdirectories such as `data/output/s62/` to
avoid cache collisions; never write under `docs/data/output/`.

The compiled-data report should begin with a dynamic data-collation section. Explain the separate
station-level haul roster and individual-level length data. Total biomass comes directly from
station catch weight; the length allocation calculus (individual weight × superindividual
representation → length-group shares → rescaling to station total biomass) applies only to
size-specific products. A data-flow schematic is useful; adapt it to the configured sources and
do not show SPD inputs when `USE_SPD: false`. Overview counts must be computed from the compiled
objects at render time rather than hard-coded.
