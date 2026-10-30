---
name: index-compile-data
description: Step 1 of the index workflow — compile bottom-trawl survey data for a species from the IMR Biotic database (and optional SPD files), apply the quantitative-catch filtering, remove duplicates, compute swept-area density, and write a data report. Use after a project is scaffolded and the user is ready to prepare the data. Needs a local BES database and IMR intranet. For sdmTMB index work outside a scaffolded index-wise project, use index-sdmtmb.
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

1. **Adapt the survey-selection document** `docs/data-report/survey-selection/compile-data.qmd` for this species and
   region: set
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
   `cruiseseriescode == "23"` → `1:2`, else `1`), `stationtype` exclusions, `distance` 0.3–5
   nmi, research/charter missions, and `startyear` window. Code 2 in `samplequality` means
   targeted sampling, not generic acceptable quality. Russian data **included by default**
   (opt-out only).
4. **Keep true zeros** — build the retained-station roster independently, aggregate the target
   catch to the same unit, and left-join it so verified absences are preserved.
5. **Remove duplicates** — flag haul ids where length sample exceeds catch; drop them; write the
   duplicate report to `ai/review/`.
6. **Optional SPD files** — only if `USE_SPD: true` (northern/offshore species). Drop SPD
   years/series already in Biotic; tag `source`. For southern/coastal species, skip SPD.
7. **Swept-area density** — apply the gear-width policy from `config.yaml` (normally a common
   25 m effective width) to compute `rho_biomass` / `rho_abundance`. Sum catch and swept area
   to the output unit before division. If a common width is used with multiple gear types,
   retain `geartype` as a fixed effect in the model.
8. **Depth** — fill missing/invalid depths from GEBCO (`ggOceanMaps::get_depth()`).
9. **Length data** — fit length–weight (`ggFishPlots::plot_lw()`) and allocate catches to
   length groups if the project needs length-based products. Raise observations within
   catchsample with a numeric `catchcount / lengthsamplecount` representation factor; do not
   round and expand rows unless a downstream method requires integer rows.
10. **Save** the compiled dataset to the root-level `data/output/` (gitignored). Region-specific
   subdirectories such as `data/output/s62/` are acceptable when two acquisition datasets share
   one project. Never create `docs/data/output/` or any other document-local output directory.

## Data report

Generate `docs/data-report/data-overview/<slug>-<region>-data-report.qmd`: station maps (ggOceanMaps), station counts
by year/depth, response-variable distributions, trawl-parameter summaries (distance, duration,
door spread, wire ratio), and the length–weight / length-group allocation. Use
`fig-format: jpeg` for rasters; keep the HTML small. (For background material, see the lookup
table in `knowledge/workflow.md`.)

For a prediction-region overview map, query quality-filtered positive target hauls across the full
study extent so split-region maps retain observations from neighbouring domains (for example, the
North Sea and Barents Sea). Calculate the prediction-region and observation bounding boxes in a
map display CRS (`MAP_CRS`, default Arctic LAEA EPSG:3995), convert each bounding box to corner
points, and pass their concatenation as `data` to `ggOceanMaps::basemap()`. This avoids distorted
geographic bounding boxes and lets the basemap derive a stable extent; use `expand.factor = 1.1`
and `coord_sf(expand = FALSE)` to keep the window tidy. The optional `MAP_SHAPEFILES` setting
controls the basemap shapefile set (default `Arctic`). Use `bathy.style = "rbg"`; before adding a
manually filled polygon layer and `scale_fill_manual()`, call `ggnewscale::new_scale_fill()` so
the polygon scale does not overwrite the bathymetry scale.

The two Step 1 documents have distinct roles and should not duplicate figures:

- `compile-data.qmd` is survey selection and coverage: survey names/codes, total catch and
  occurrence, survey positions, gear overview/table, timing, filtering decisions, and a
  filtering-script appendix.
- `<slug>-<region>-data-report.qmd` is the compiled-data overview: final station map, effort
  through time, depth and response distributions, continuous effort checks, length products,
  and diagnostics. Begin this document with a dynamic **Data collation** explanation covering
  station-level and individual-level data, then describe the length-group calculation explicitly:
  Keep total biomass directly tied to station catch weight; use observed or estimated individual
  weight multiplied by superindividual representation only for the size-specific products, then
  group into length shares and rescale to station total biomass. Include a schematic of the actual
  data flow; omit SPD branches when `USE_SPD: false`.
  Record individual-level summary metadata (length-record count, station count, and observed
  individual-weight count) in compiler diagnostics so the report can describe the dataset without
  hard-coded values or exposing raw individual records.

Every figure and table must have a caption. Use stable `fig-cap`/`tbl-cap` chunk metadata or an
explicit table caption, with explicit Quarto labels and cross-reference settings so captions
render as numbered Figures/Tables; keep the region identifier in the data-overview filename for split
N62/S62 (or equivalent) projects.

## Before rendering

**Code-review the compilation chunks first** (filtering is easy to get subtly wrong), then
render via `index-render` in a screen session with a log in `logs/`. Write a memory note
recording the survey list, filter choices, and any duplicates found.

## Next

Step 2 — fit the first feasible model (`index-fit-model`).
