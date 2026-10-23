---
name: index-make-regions
description: Create, modify, validate, order, save, or map named spatial study-region polygons for survey-data extraction, sdmTMB prediction grids, stock assessment, or other spatial analyses. Use when a user asks for non-overlapping regions, a study area, region boundaries, a region GeoPackage, polygon validation, or a ggOceanMaps region map.
---

# Make analysis regions

Create a valid, named polygon partition for analysis. Read `knowledge/regions.md` in full before changing geometry.

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Confirm the specification first

Inspect candidate input files and the project configuration read-only, then ask the user for the missing decisions before any geometry or file write. Offer concise, reasonable choices for:

1. **Purpose and domain:** data-extraction domain, model/prediction domain, or both; identify the master polygon that the final regions must exactly cover.
2. **Boundary sources:** supplied regions, depth-limited prediction footprint, ICES/EEZ areas, latitude/longitude caps, survey coverage, or a specified combination. State the proposed precedence where sources conflict.
3. **Partition rule:** which named polygon has priority where input polygons overlap, or whether an overlap should be split by an explicit boundary.
4. **Output name:** if `data/gis/regions.gpkg` already exists, **never overwrite it**. Ask for a distinct filename, offering names such as `regions_<study>_v1.gpkg` or `regions_<year>_<domain>.gpkg`. Also confirm the GeoPackage layer name if it is not `regions`.

Use the study-area CRS already established by the project for all geometry operations, area checks, and the final GeoPackage. Do not silently substitute a geographic CRS for an analytical one. Transform a copy to WGS84 only when ggOceanMaps requires it for display.

## Build and validate

1. Read and make input geometry valid. Preserve source geometries; construct derived regions in a separate object.
2. Build the master domain and every candidate region in the project CRS. Apply explicit rules (for example, depth footprint subtraction, EEZ subtraction, or latitude caps) in the agreed order. Densify only an explicitly analytical boundary, and record the segment length.
3. Make a partition: apply the agreed overlap priority with `st_difference()` or split at the agreed boundary. Keep all named pieces needed to cover the master domain.
4. Validate in the project CRS. Every output feature must satisfy `st_is_valid()`. Confirm that pairwise overlap area is within a declared numerical tolerance, and compare the union of all output regions with the master domain to quantify both uncovered gaps and area outside the domain. Do not call the result gap-free unless both are within tolerance.
5. Create a deterministic southwest-to-northeast order unless the user specifies another one: order interior-point latitude ascending, then longitude ascending. Store `region_order_index`; use `factor(region, levels = region_order)` in all legends, facets, and tables.
6. Save only after validation to the confirmed new GeoPackage. Include `region` and `region_order_index`; keep the project CRS. Never use `delete_dsn`, `delete_layer`, or an equivalent overwrite option on an existing user file.
7. Plot the final region object using `ggOceanMaps::basemap(x, legends = FALSE, bathymetry = TRUE, bathy.style = "rbg", bathy.alpha = 0.5)`, where `x` is the region `sf` object. Overlay the filled named polygons and their borders; use `ggnewscale::new_scale_fill()` before a manual polygon fill scale if bathymetry has already used the fill scale.
8. Save a concise reproducibility note in the project memory: inputs, CRS, master domain, boundary/priority decisions, validation values, order, and output file/layer. Add a report or script that can rebuild the GeoPackage without manual GIS edits.

## Deliver

Report the output GeoPackage and layer, CRS, ordered region names, validity status, overlap/gap diagnostics, and the rendered map. Distinguish exact validation from tolerances caused by spatial precision.
