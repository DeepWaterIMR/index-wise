# The R package ecosystem

Use these packages; don't reinvent what they already do. Everything downstream of the data
comes from the modelling stack; data access comes from BAIT.

## Data access (via BAIT)

BAIT owns the Biotic data layer. Read its knowledge/skills rather than duplicating them here.

| Package | Role | Via |
|---|---|---|
| [BioticExplorerServer](https://github.com/DeepWaterIMR/BioticExplorerServer) | Builds/updates the DuckDB Biotic database | BAIT `biotic-server-setup` |
| DBI + duckdb + tidyverse | Connect and query lazily | BAIT `biotic-connect`, `biotic-query` |
| [RstoxUtils](https://deepwaterimr.github.io/RstoxUtils/) | Parse NMD Biotic XML / SPD files | `processBioticFile()` |

## Modelling

| Package | Role | Key functions |
|---|---|---|
| [sdmTMB](https://github.com/sdmTMB/sdmTMB) | Spatiotemporal GLMMs (the index model) | `sdmTMB()`, `make_mesh()`, `add_utm_columns()`, `predict()`, `get_index()`, `get_index_split()`, `sanity()`, `sdmTMB_cv()` |
| [sdmTMBextra](https://github.com/pbs-assess/sdmTMBextra) | Barrier meshes, extras | `add_barrier_mesh()` |
| [sdmTMBexperiments](https://github.com/DeepWaterIMR/sdmTMBexperiments) | This workflow's helpers | grids, diagnostic maps, comparisons, retro, mesh CV (see `sdmtmbexperiments.md`) |
| [glmmTMB](https://glmmtmb.github.io/glmmTMB/) | CPUE GLMMs with crossed random effects (`cpue-models.md`) | `glmmTMB()`, `predict(re.form = NA)` |
| [mgcv](https://cran.r-project.org/package=mgcv) | CPUE GAMMs with spatial and random-effect smooths | `bam()`, `gam()`, `predict(type = "lpmatrix")` |
| [DHARMa](https://cran.r-project.org/package=DHARMa) | Simulation residuals, grouped dispersion | `simulateResiduals()`, `recalculateResiduals()`, `testDispersion()` |

## Figures & maps

| Package | Role | Key functions |
|---|---|---|
| [ggplot2](https://ggplot2.tidyverse.org/) | All static figures | `ggplot()`, `geom_*`, `theme_bw()` |
| [ggOceanMaps](https://mikkovihtakari.github.io/ggOceanMaps/) | Static maps with land/bathymetry (the default map tool) | `basemap()`, `qmap()`, `get_depth()` |
| [ggFishPlots](https://deepwaterimr.github.io/ggFishPlots/) | Length–weight & life-history from `indall` | `plot_lw()`, `plot_maturity()`, `plot_growth()` |
| cowplot / patchwork | Multi-panel layouts | `plot_grid()` |

## Documents

| Package | Role |
|---|---|
| quarto / knitr / rmarkdown | Render the `.qmd` documents |
| kableExtra / flextable | Tables (HTML/PDF/Word) |
| sf | Spatial polygons / grids |

## Install lines (not all on CRAN)

```r
install.packages(c("sdmTMB", "ggOceanMaps", "sf", "tidyverse", "quarto", "kableExtra"))
# install.packages("remotes")
remotes::install_github("DeepWaterIMR/sdmTMBexperiments")
remotes::install_github("pbs-assess/sdmTMBextra")
remotes::install_github("DeepWaterIMR/ggFishPlots")
# suggested by some helpers:
install.packages(c("concaveman", "blockCV", "inlabru", "DHARMa", "ggspatial", "ggnewscale", "pbapply"))
# commercial CPUE (mgcv ships with R):
install.packages("glmmTMB")
```

## Conventions

- **Attach `sdmTMBexperiments`** (`library()`, not just `::`) so ggOceanMaps' bundled land
  data is available to the map helpers.
- **Read reference data (species, surveys, gear) from the Biotic database via BAIT**, not by
  hard-coding.
- **Maps**: `ggOceanMaps::qmap()` for a quick look; `basemap()` for publication figures with
  bathymetry. The sdmTMBexperiments map helpers build on `basemap()`.
