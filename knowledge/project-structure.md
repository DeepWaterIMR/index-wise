# The generated project structure

`index-new-project` copies `project-template/` and stamps it with `config.yaml` to produce a
**new project folder** for one species (or a small group of related species). This is the
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
│   └── report_helpers.R  # Narrative software citations from citation()
├── docs/
│   ├── render.R         # Stage-aware HTML rendering
│   ├── assets/          # references.bib, ICES JMS CSL, included static assets
│   └── data-report/
│       ├── survey-selection/compile-data.qmd
│       ├── data-overview/<species>-<region>-data-report.qmd
│       ├── fit/fit.qmd
│       ├── validation/validate.qmd
│       └── <species>/   # report.qmd and optional *-section.qmd includes
├── data/
│   ├── source/          # Local source data and supplied GIS polygons; ignored
│   └── output/          # Fits, grids, predictions and indices; ignored
├── figures/             # Exported figures; ignored except README
├── logs/                # Temporary render logs; ignored except README
├── ai/
│   ├── memory/          # Shared project memory: read MEMORY.md first
│   ├── tests/           # Small validation checks and synthetic fixtures
│   └── review/          # Reviews and audit outputs; ignored except README
└── config/              # Tooling configuration, separate from analysis settings
```

Add `website/` only for projects with a website. Add numbered analysis scripts under `R/`
as the project develops; do not generate empty compiler scripts that pretend to implement
the method. All documents and their rendered outputs stay under `docs/`.


## Rules

- **`data/`, `logs/`, `ai/review/` are git-ignored.** Only code, docs, `ai/memory/`, and
  `config.yaml` are committed. No raw data or private paths in tracked files.
- **`config.yaml` is the single source of truth** for species, `filter_sp`, surveys, response
  variables, length groups, study area / CRS / grid size / mesh cutoff, gear-width policy, and
  output paths. Documents read from it (via `R/0_setup.R`); they do not hard-code settings.
- **Multiple species** → one `docs/data-report/<species>/` folder each, sharing earlier reports under `docs/data-report/` where the compiled dataset supports it. Otherwise scaffold one project
  per species.
- **Outputs cache to `data/output/`.** Expensive fits, prediction grids, predictions, and
  indices are saved there so re-renders load instead of recomputing (toggle-controlled — see
  `rendering.md`).
- **Regions belong in data-document filenames.** Set `REGION_SLUG` in `config.yaml`; the
  scaffold stamps it into `<species>-<region>-data-report.qmd`. This keeps split N62/S62
  projects and their rendered outputs unambiguous.
- **Project memory lives in `ai/memory/`.** Agents read `ai/memory/MEMORY.md` first and write new
  memory files there — not in the agent's local per-machine memory.

## `config.yaml` fields (stamped by `scaffold.R`)

`SPECIES_NAME` (display), `SPECIES_SLUG` (folder/file slug), `SPECIES_LATIN`, `FILTER_SP`
(Norwegian commonname value(s)), `SURVEYS` (cruise-series labels to include), `USE_SPD` (true/false),
`RESPONSE` (`biomass`/`abundance`), `LENGTH_GROUPS`, `OVER_CM` threshold, `ASSESSMENT_MODEL`,
`FIRST_YEAR`, `CRS` (EPSG), `GRID_KM`, `MESH_CUTOFF_KM`, `BARRIER` (true/false), `GEAR_WIDTH`
(`per_gear`/set value), `INCLUDE_RUSSIAN` (default true), `SELECTED_INDEX`.
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
in report metadata. `BASE_SIZE` defaults to 12; `FIGURES_DIR` defaults to `figures/`.
