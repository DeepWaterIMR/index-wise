# The generated project structure

`index-new-project` copies `project-template/` and stamps it with `config.yaml` to produce a
**new project folder** for one stock, or for several related stocks (e.g. two species for one
benchmark) that share the data compilation and the documents. This is the
"output" structure — the user's own repo. index-wise itself is never this structure.

```
<species>-index/
├── AGENTS.md / CLAUDE.md # Agent contract and pointer
├── config.yaml          # Species, area, model settings, authors and affiliations
├── VERSION              # version: 0.1.0 and scaffold date
├── .here / _quarto.yml   # Project root and editor-preview execution directory
├── .gitignore
├── R/
│   ├── 0_setup.R         # Packages, config, theme and model helpers
│   ├── compile_functions.R # Step 1 compilation: filters, stock area, true zeros, length products
│   ├── plot_helpers.R    # Fixed cruise-series/gear colours, stock-area polygon
│   ├── index_helpers.R   # Effort, index year, references, balance, bridging, robustness
│   ├── cpue_helpers.R    # Commercial CPUE records, indices, diagnostics, bootstrap
│   ├── report_helpers.R  # Software citations, model data, CV folds and SE, stage tables
│   ├── fishable_length.R # Fishable-length threshold from commercial lengths
│   ├── run_models.sh     # Unattended steps 2-5 for one stock on the server (knowledge/pipeline.md)
│   ├── validation/       # Model-selection stage runner (stage_lib.R, run_candidate.R, assemble_stage.R, run_species.sh, smoke_test.R) and sync_final_model.R; caches in <OUTPUT_DIR>/<stock>/selection/
│   ├── report/           # Final-report computations (report_lib.R, report_compute.R, run_report.sh) and figures (report_plots.R); results cached in <OUTPUT_DIR>/<stock>/report/
│   └── hpc/              # Optional cluster jobs for the selection (slurm/) and rename_caches.R
├── docs/
│   ├── render.R         # Stage-aware HTML rendering
│   ├── assets/          # references.bib, ICES JMS CSL, included static assets
│   ├── data/            # Fixed data documents (knowledge/data-documents.md)
│   │   ├── <stock>-1-summary.qmd
│   │   ├── <stock>-2-survey-selection.qmd
│   │   └── <stock>-3-data.qmd
│   ├── background/      # <stock>-0-background.qmd: stock background and fishable length
│   └── sdmtmb/          # sdmTMB model documents
│       ├── fit/<stock>-4-fit.qmd
│       ├── validation/<stock>-5-validate.qmd   # reads the R/validation caches
│       ├── <stock>/<stock>-6-report.qmd        # reads the R/report caches
│       ├── sections/    # *-section.qmd shared by the stock reports
│       └── cpue/cpue.qmd # optional commercial CPUE index (config CPUE:)
├── publish-site.sh       # Optional: copy the rendered HTML to a website repository (SITE_DIR)
├── data/
│   ├── source/          # Local source data and supplied GIS polygons; ignored
│   └── output/<stock>/  # Fits, grids, predictions, selection and report caches; ignored
├── figures/             # Exported figures; ignored except README
├── logs/                # Temporary render logs; ignored except README
├── ai/
│   ├── memory/          # Shared project memory: read MEMORY.md first
│   ├── tests/           # Checks: stock parity, AI statement, fishable biomass
│   └── review/          # Reviews and audit outputs; ignored except README
└── config/              # Tooling configuration, separate from analysis settings
```

### Document root (`DOCS_DIR`)

The four document folders `assets/`, `background/`, `data/` and `sdmtmb/` sit under one root,
`DOCS_DIR` in `config.yaml` (default `docs`); `docs/render.R` always stays at `docs/render.R`.
An index made for a stock assessment nests them one level deeper, `DOCS_DIR: "docs/benchmark"`,
so later assessment rounds can add sibling roots (`docs/assessment-2027/`, ...) beside it:

```
docs/render.R
docs/benchmark/{assets,background,data,sdmtmb}/
docs/assessment-2027/{assets,background,data,sdmtmb}/   # later round
```

`scaffold_index()` picks the root from its `docs_dir` argument, else `DOCS_DIR` when it is not
`docs`, else `docs/benchmark` when `ASSESSMENT_MODEL` is set, else `docs`. R code builds paths as
`here::here(cfg$DOCS_DIR %||% "docs", "assets", ...)`; YAML paths inside documents stay relative
(`../assets/...` from `data/` and `background/`, `../../assets/...` from `sdmtmb/<report>/`), so
they work in both layouts. Paths in this knowledge base such as `docs/sdmtmb/fit/<stock>-4-fit.qmd` are
relative to the document root; read `docs/` as `DOCS_DIR`.

Add `website/` only for projects with a website. Add numbered analysis scripts under `R/`
as the project develops; do not generate empty compiler scripts that pretend to implement
the method. All documents and their rendered outputs stay under `docs/`.


## Rules

- **`data/`, `logs/`, `ai/review/` are git-ignored.** Only code, docs, `ai/memory/`, and
  `config.yaml` are committed. No raw data or private paths in tracked files.
- **`config.yaml` is the single source of truth** for species, `filter_sp`, surveys, response
  variables, length groups, study area / CRS / grid size / mesh cutoff, gear-width policy, and
  output paths. Documents read from it (via `R/0_setup.R`); they do not hard-code settings.
- **Stocks.** The numbers give the reading order: `<stock>-0-background` … `<stock>-6-report`.
  `<stock>` is the stock key: a `SPECIES_SETTINGS` entry, or `STOCK_SLUG` for a single stock
  (default the species slug, plus the region slug for a split domain). Each document sets
  `index_species <- "<stock>"` before sourcing `R/0_setup.R`, which merges that stock's
  settings over the shared ones (`select_stock()`) and points `OUTPUT_DIR` to
  `data/output/<stock>/`. With several stocks the first one's documents are the masters:
  edit them and run `Rscript ai/tests/test-stock-parity.R write`; everything that differs
  between stocks lives in `config.yaml`. Stocks with different data sources or assessments
  are better as separate projects.
- **Outputs cache to `data/output/`.** Expensive fits, prediction grids, predictions, and
  indices are saved there so re-renders load instead of recomputing (toggle-controlled — see
  `rendering.md`).
- **The stock names the data documents.** `STOCK_SLUG` (default: species slug, plus the
  region slug for split domains, e.g. `atlantic-halibut-n62`) prefixes `docs/data/<stock>-*.qmd`.
  This keeps split N62/S62 projects and their rendered outputs unambiguous.
- **Project memory lives in `ai/memory/`.** Agents read `ai/memory/MEMORY.md` first and write new
  memory files there — not in the agent's local per-machine memory.

## `config.yaml` fields (stamped by `scaffold.R`)

`SPECIES_NAME` (display), `SPECIES_SLUG` (folder/file slug), `SPECIES_LATIN`, `STOCK_SLUG`
(data-document prefix), `STOCK_CODE`, `AREA_LABEL` (area in titles), `PURPOSE` (one sentence),
`STOCK_SUBAREAS` + `ICES_AREAS_FILE` (ICES-area stock definition; empty → `REGION_FILE` polygon),
`MAP_LIMITS`, `LENGTH_LIMITS`, `CRUISE_SERIES_LABELS`, `FILTER_SP`
(Norwegian commonname value(s)), `SURVEYS` (cruise-series labels to include), `USE_SPD` (true/false),
`RESPONSE` (`biomass`/`abundance`), `LENGTH_GROUPS`, `OVER_CM` threshold, `ASSESSMENT_MODEL`,
`FIRST_YEAR`, `CRS` (EPSG), `GRID_KM`, `MESH_CUTOFF_KM`, `BARRIER` (true/false), `GEAR_WIDTH`
(`per_gear`/set value), `INCLUDE_RUSSIAN` (default true), `SELECTED_INDEX`.

Effort, time step and catchability: `EFFORT` (`density`/`offset`), `INDEX_YEAR_START_MONTH`
and `INDEX_YEAR_LABEL` (`start`/`end`), `SURVEY_EFFECT`, `REFERENCE_SURVEY`,
`CATCHABILITY_TERMS`, `CATCHABILITY_REFERENCE`, `MIN_DEPTH`. Bridging and robustness:
`LATE_COMPONENTS` (`{column, values}`), `PREVIOUS_INDEX_FILE`, `REVISION_TOLERANCE`, and
`ROBUSTNESS` (`subsample_props`, `subsample_reps`, `start_year_peels`, `downweight_years`,
`downweight_value`). Each has a default in `R/index_helpers.R` or the documents, so older
configs keep working. The optional `CPUE:` block configures the commercial CPUE document: the
local extract (`file`, `landings_file`), `source`, `unit`, plausible `ranges`, core-fleet
thresholds, `effort_treatment`, `engine` (glmmTMB/mgcv/sdmTMB), mesh and grid, the prediction
`reference`, `final_month` and `bootstrap_n`.
Several stocks: `SPECIES_SETTINGS` (one block per stock, merged over the shared keys).
Model selection: `MESH_LADDER_KM` and the `SELECTION` block (`CV_TOP_N`, `MESH_TOL`, `GRID_TOL`,
`WINDOW`, `GRID_LADDER_KM`, `IID_YEAR_ONLY`, `FIXED_EXTRA`), `MONTH_TERM`
(`smooth`/`factor`/`none`), `REFERENCE_GEAR_MODEL`. Report: `FINAL_MODEL` (written by
`R/validation/sync_final_model.R`), `FISHABLE_YEAR_EFFECT`, `SENSITIVITY_OVER_CM`,
`SENSITIVITIES` (refits of type `drop`, `keep`, `offset`, `fishable_threshold`),
`REGIONS_FILE`/`REGIONS` (regional split; ICES divisions without them),
`ASSESSMENT_CANDIDATE_INDICES`/`ASSESSMENT_RECOMMENDED_INDEX`
(the IID + year hand-offs and the recommendation; legacy `SPICT_*` names are read),
`ASSESSMENT_MODEL` (named in the document text), `SITE_DIR` (optional website clone).

For split domains also set `REGION`, `REGION_SLUG`, `REGION_FILE`, and `REGION_LAYER`. For
high-latitude overview maps, optionally set `MAP_CRS` (default EPSG:3995, Arctic LAEA) and
`MAP_SHAPEFILES` (default `Arctic`).

When acquisition uses a broader reporting polygon than the model domain, set
`ACQUISITION_REGION`/`ACQUISITION_REGION_LAYER` to the broader feature, keep `REGION` as the
model-domain label, and set `ADD_REGION_IDENTIFIER: true` with `PARTITION_REGION` and
`PARTITION_REGION_LAYER`. The compiled station data should then retain all qualifying hauls in
the acquisition polygon and carry a `region` field for later model-stage filtering.

All main documents follow `wise-writing.md`: human authors and affiliations, a
`published-title: "Version"` date label, narrative software citations, and folded code.
The scaffold requires `AUTHORS` and `AFFILIATIONS` using wise-writing's schema:

```yaml
AUTHORS:
  - name: "<accountable human author>"
    affiliation: institute
AFFILIATIONS:
  - id: institute
    name: "<institution name>"
```

Replace the example values with confirmed human metadata. No private database paths belong
in report metadata. `BASE_SIZE` defaults to 12; `FIGURES_DIR` defaults to `figures/`; `DOCS_DIR` defaults to `docs`.

## Projects scaffolded before 0.3.0

Version 0.3.0 changed the project layout: numbered per-stock documents
(`<stock>-0-background` … `<stock>-6-report`) with shared report sections, `SPECIES_SETTINGS`
for one or several stocks, the `SELECTION` and `SENSITIVITIES` blocks, the stage runner in
`R/validation/` with `sync_final_model.R`, and the unattended `R/run_models.sh`. A flat
0.2.x config is still read as one stock, and the legacy `SPICT_*` index keys are still read.
Do not migrate an existing project silently: copy new helpers or documents into it only on
the maintainer's request, and record what was taken in its `ai/memory/`.
