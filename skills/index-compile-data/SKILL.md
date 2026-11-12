---
name: index-compile-data
description: Step 1 of the index workflow — compile bottom-trawl survey data for a species from the IMR Biotic database (and optional SPD files), apply the quantitative-catch filtering, remove duplicates, compute swept-area density, and write a data report. Use after a project is scaffolded and the user is ready to prepare the data. Needs a local BES database and IMR intranet. For sdmTMB index work outside a scaffolded index-wise project, use index-sdmtmb.
---

<!-- pack-resources:start -->
**Pack resources:** the `index-wise` root is `~/.index-wise/config.json` → `index_template_path`, else `~/.fiskwise/config.json` →
`components.index-wise.path`, else the checkout containing this skill. Paths such as `knowledge/`
and `project-template/` are relative to that root, never `../../` from a skills folder; resolve
links that leave this skill's folder against the source skill there. Use absolute paths.
<!-- pack-resources:end -->


# Step 1 — Compile & report the data

Goal: produce one clean, filtered dataset of bottom-trawl stations with true absences and
swept-area density for the target species, plus a data report. **Read
`knowledge/data-filtering.md` in full and reproduce its logic exactly** — this is where indices
most often go wrong.

**Prerequisites:** a locally installed BES Biotic database and an **IMR intranet connection**.
For other survey data, skip the Biotic extraction and deliver a station table that meets the
own-data contract in `knowledge/data-filtering.md`, then document it in the data report.
Use BAIT for data access: `biotic-server-setup` (if the DB is missing/stale), `biotic-connect`,
`biotic-query`, `taxaindex` (species) and the cruise-series lookup (surveys).

In rendered project documents, name the scientific source as the **IMR Biotic database**.
BAIT is the agent-side guidance and connection workflow; it is not a separate data source and
should not be described as one in the data report. Do not copy machine-specific database paths
into the template or generated project.

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Work

0. **Check the database date first.** Record when the local Biotic database was last updated
   (BAIT `biotic-server-setup`) and the latest year it holds, and compare with the intended
   last complete year. An outdated database truncates the series silently: one project's
   compile ended in 2020 instead of 2025, and a whole model-selection round ran on the short
   series before it was noticed. Update the database before compiling, not after.
   Keep every lazy query bounded: compute date literals in R before the query (date
   extraction inside `filter()` does not translate to DuckDB), and `count()` before every
   `collect()` against `MAX_COLLECT_ROWS`.

1. **Adapt the survey-selection document** `docs/data/<stock>-2-survey-selection.qmd` for this species and
   stock area: set
   `filter_sp` and the survey list from `config.yaml`. Read `stnall` (stations) and `indall`
   (individual/length) from the Biotic database via BAIT.
   Keep the nomenclature explicit: a **survey** is one cruise, whereas a **cruise series** is
   the time-series grouping of its surveys. Include an individual survey when it has at least
   one qualifying positive target catch; assign included coded surveys to their cruise series
   only afterward. Uncoded surveys are assessed individually.
   Implement this in two stages: first collect the qualifying `missionid` values from positive
   target catches after the standard filters and exact region test; then retain all valid regional
   hauls whose `missionid` is in that qualifying set. Do not select all hauls by cruise-series
   code, because that backfills surveys in the same time-series that failed the survey-level
   positive-catch or sampling-quality rule.
   If survey acquisition covers a broader reporting polygon than the later model domain, use
   `ACQUISITION_REGION`/`ACQUISITION_REGION_LAYER` for the acquisition polygon and retain
   `REGION` as the model-domain label. With `ADD_REGION_IDENTIFIER: true`,
   `PARTITION_REGION`/`PARTITION_REGION_LAYER` should be used to add a `region` column after
   exact spatial filtering; this lets the full acquisition dataset be compiled once and split
   during model fitting.
2. **Define the haul key and catchsample logic** from `knowledge/data-filtering.md`. Use
   `missionid + serialnumber` in BES or the native mission tuple plus `serialnumber`; inspect
   catchparts and comments before aggregation.
3. **Apply the station filter** from `knowledge/data-filtering.md`: the documented
   survey-specific `gearcondition` set, the conditional `samplequality` rule (coastal series
   `cruiseseriescode == "23"` → `1:2`, else `1`), `stationtype` keep-list (missing, 1, 3, 9, 13), `distance` 0.3–5
   nmi, research/charter missions, and `startyear` window. Code 2 in `samplequality` means
   targeted sampling, not generic acceptable quality. Russian data **included by default**
   (opt-out only).
4. **Keep true zeros** — build the retained-station roster independently, aggregate the target
   catch to the same unit, and left-join it so verified absences are preserved.
5. **Remove duplicates** — flag haul ids where length sample exceeds catch; drop them; write the
   duplicate report to `ai/review/`.
6. **Optional SPD files** — only if `USE_SPD: true` (northern/offshore species). Tag `source`,
   match SPD and Biotic hauls with `RstoxUtils::match_spd_biotic()` (≤ 1 km, ≤ 3 h), and drop
   the duplicated SPD cruises with `RstoxUtils::drop_spd_duplicates()`, which gives the Biotic
   copies the SPD cruise series. For southern/coastal species, skip SPD.
6b. **Documented exclusions** — apply `config.yaml` `EXCLUDE_CRUISES` (platform + cruise).
   Entries come only from the influence workflow (`knowledge/influence-diagnostics.md`).
7. **Swept-area density** — apply the gear-width policy from `config.yaml` (normally a common
   25 m effective width) to compute `swept_area` with `swept_area_nmi2()` and
   `rho_biomass` / `rho_abundance`. Keep `swept_area` in the output (`EFFORT: offset` and the
   Step 2 scale check use it). Sum catch and swept area to the output unit before division. If
   a common width is used with multiple gear types, retain `geartype` as a fixed effect.
8. **Index year** — add `index_year` from `startyear` and `month` (`index_year()`, config
   `INDEX_YEAR_START_MONTH`/`INDEX_YEAR_LABEL`); keep `startyear` as the calendar year. See
   `knowledge/data-filtering.md` *Index year*.
9. **Depth** — fill missing/invalid depths from GEBCO (`ggOceanMaps::get_depth()`).
10. **Catchability covariates** — `add_response_and_covariates()` adds `hour` (UTC) for every
    haul and `sun_altitude` (`suncalc`) when `CATCHABILITY_TERMS` includes it.
11. **Length data** — fit length–weight (`ggFishPlots::plot_lw()`) and allocate catches to
   length groups if the project needs length-based products. Raise observations within
   catchsample with a numeric `catchcount / lengthsamplecount` representation factor; do not
   round and expand rows unless a downstream method requires integer rows. Record
   `n_measured` per haul. **A positive haul without measured individuals is never zero in the
   class products**: `add_fishable_biomass()` imputes its share hierarchically and flags it in
   `fishable_imputed` (`knowledge/data-filtering.md` *Individual data: missing is not zero*).
12. **Save** the compiled dataset to the root-level `data/output/` (gitignored). Region-specific
   subdirectories such as `data/output/s62/` are acceptable when two acquisition datasets share
   one project. Never create `docs/data/output/` or any other document-local output directory.

## Documents

The data step has three documents per stock in `docs/data/` with a **fixed structure**:
`<stock>-1-summary.qmd`, `<stock>-2-survey-selection.qmd` and `<stock>-3-data.qmd`. Read
`knowledge/data-documents.md` and keep its file names, section headings, figures, tables and
writing rules; adapt only the content. The shared code is in `R/compile_functions.R`
(compilation, stock-area rule, length–weight, fishable/length products) and
`R/plot_helpers.R` (fixed colours, stock-area polygon); call these rather than writing new
code in the documents.

- `<stock>-2-survey-selection.qmd` runs the compilation and documents the stock-area map,
  haul filter (criteria table and filter listing), surveys and cruise series, catch and effort,
  positions, gear, timing, gross-error screening and other data types. No prediction-region map
  here; the prediction region belongs to the fit document.
- `<stock>-3-data.qmd` is the compiled-data report: final station map, effort through time,
  depth and response distributions, trawl parameters, length products and diagnostics. Begin it
  with a dynamic **Data collation** explanation covering station-level and individual-level
  data, then describe the length-group calculation explicitly: keep total biomass tied to
  station catch weight; use observed or estimated individual weight multiplied by
  superindividual representation only for the size-specific products, then group into length
  shares and rescale to station total biomass. Record individual-level summary metadata in the
  compiler diagnostics so the report has no hard-coded values.
- `<stock>-1-summary.qmd` holds the abstract (placeholder until Step 4), purpose, document
  list, AI statement and the central data table; model and index sections are filled in at the
  end of the workflow.

In `<stock>-3-data.qmd`, also show the index-year mapping, the survey × year and gear × year
balance (`design_balance()`; a flagged level needs a decision before modelling) and the
terminal-year counts of `LATE_COMPONENTS`. Catchability covariates (`hour`, and `sun_altitude`
when `CATCHABILITY_TERMS` asks for it) are added by `add_response_and_covariates()`.

Every figure and table has a caption and a preceding sentence that refers to it. Use
`fig-format: jpeg`; keep the HTML small. (For background material, see the lookup table in
`knowledge/workflow.md`.)

## Before rendering

**Code-review the compilation chunks first** (filtering is easy to get subtly wrong), then
render via `index-render` in a screen session with a log in `logs/`. Write a memory note
recording the survey list, filter choices, and any duplicates found.

## Next

Step 2 — fit the first feasible model (`index-fit-model`).
