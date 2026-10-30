# The assessment-index hand-off

The one format in which index-wise passes a survey index to an assessment model. Step 4 writes
it; spict-wise and gadget-wise read it. Any other producer (a stratified index, a CPUE
standardisation) can write the same object so the consumers need no special code.

Producer: `project-template/R/assessment_index_handoff.R` → `build_assessment_index_handoff()`.
Tests: `config/test-assessment-index-handoff.R` here and `config/test-index-contract.R` in
spict-wise, which also runs this producer when the sibling checkout is present.

## Schema version 1

An `.rds` file (default `assessment-index.rds`) holding a list:

| Element | Content |
|---|---|
| `schema_version` | `1L` |
| `selected_name` | Name of the chosen index product (`SELECTED_INDEX` in the producer's config) |
| `observations` | Data frame `year`, `est`, `lwr`, `upr`, `se`: unique integer years, `est > 0`, `lwr ≤ est ≤ upr`, `se > 0` |
| `metadata$units` | e.g. `"relative"`, `"tonnes"`, `"numbers"` |
| `metadata$uncertainty` | `list(column = "se", scale = "log", measure = "standard_error")` |
| `metadata$index_type` | e.g. `"survey biomass"`, `"survey abundance"` |
| `metadata$timing` | Fraction of the year the observations refer to, 0 to 1 |
| `metadata$spatial_scope` | The area the index covers |
| `metadata$provenance` | Producer project, commit, model specification, render date |

## Consumers

| Pack | Reader | What it uses |
|---|---|---|
| spict-wise | `read_assessment_index_handoff()` in its `R/index_contract.R` | Checks `selected_name` and `timing` against config; `se` becomes `stdevfacI` |
| gadget-wise | `prepare_index()` in the IMR template's `R/data_loop_bait.R` | Writes `index_<Name>.csv`; `index_type` containing "abundance" gives a `number` column, otherwise `weight` |

## Rules

- Change the schema only with a new `schema_version`, and update both consumers and their tests
  in the same change. Consumers reject versions they do not know.
- The consumer copies the file to its `data/source/` and records the producer commit in its
  project memory.
- An index that feeds an assessment is usually fitted with `spatiotemporal = "iid"` and year as a
  fixed effect (see `model-selection.md`); say which was carried.
