# Worked example — beaked redfish

This is the reference example, matching the published paper and the beaked benchmark so a
generated index can be compared against a known result.

- **Config**: [`config.yaml`](config.yaml) — beaked redfish (*Sebastes mentella*), ICES 1-2,
  five surveys, SPD included, delta-lognormal AR1, 10 km grid, 60 km mesh, selected index
  "Over 30 cm biomass" feeding SPiCT.

## Scaffold it

```r
source("<index_template_path>/scaffold.R")
scaffold_index("examples/redfish/config.yaml", target = "../snabeluer-index", dry = TRUE)  # preview
scaffold_index("examples/redfish/config.yaml", target = "../snabeluer-index")              # create
```

Then follow the four steps (`index-compile-data` → `index-fit-model` →
`index-validate-model` → `index-final-report`). Compiling the data needs a local BES database
and an IMR intranet connection.

## Background material (not distributed here — no data)

Steps 1–4 are index-wise's own documents in `project-template/docs/`, improved directly as
the routine matures — they are not named after or tied to any source paper's internal
document names. If you want the history behind the method, or expected results to sanity
check against, see:

- The (IMR-internal) reference projects listed in
  [`knowledge/workflow.md`](../../knowledge/workflow.md).
- Vihtakari et al. (2026), *ICES J. Mar. Sci.*,
  [doi:10.1093/icesjms/fsag009](https://doi.org/10.1093/icesjms/fsag009).

Nothing here contains data or private paths.

Fill `AUTHORS` and `AFFILIATIONS` with confirmed human metadata before scaffolding.
