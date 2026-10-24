# Contributing to index-wise

index-wise is a **public knowledge pack** for building sdmTMB survey indices. It contains
**instructions only — never data**. Contributions are welcome; please keep the following in
mind.

## The golden rule: no data, no private paths

- **Never commit data** (`.rds`, `.rda`, `.csv`, `.duckdb`, `.gpkg`, `.shp`, station
  coordinates, raw records) — the `.gitignore` blocks common extensions as a safety net, but
  the responsibility is yours.
- **Never commit private or local paths** (`/Users/...`, `OneDrive`, `CloudStorage`, BES
  database paths). Use placeholders (`{{...}}`) and environment variables.
- Examples and recipes use **code and rounded/synthetic values**, never real data.

## What lives where

- **`knowledge/`** — the shared source of truth (method, filtering, sdmTMB, helpers,
  packages, project structure, rendering). Prefer improving these over duplicating guidance
  in skills.
- **`skills/index-*/SKILL.md`** — one skill per recurring task. Keep the `SKILL.md` short and
  link into `knowledge/` for detail. Frontmatter must have `name` and `description`.
- **`project-template/`** — the skeleton stamped into each new project. Analytical qmd/R
  content is **adapted** from the reference projects (`ref-index-paper`,
  `ref-assessment-index`), with all private paths/data stripped and species parameterised via
  `config.yaml`.
- **`examples/`** — worked examples (filled `config.yaml` + notes).

## Style

- Markdown wrapped at ~92 columns; **`.qmd`/`.Rmd` prose is NOT hard-wrapped** (soft-wrap
  editors) — one paragraph per line.
- R uses tidyverse syntax; match the surrounding file's pipe (`|>` / `%>%`) and comment
  density.
- Helpers belong in [sdmTMBexperiments](https://github.com/DeepWaterIMR/sdmTMBexperiments),
  not duplicated here. If a generic helper is missing, propose it there.

## Testing a change

Before opening a PR:

1. Run the privacy check: `grep -rIn -e '/Users/' -e 'OneDrive' -e 'CloudStorage' .` — must
   find nothing outside placeholders.
2. Confirm every `SKILL.md` has valid frontmatter and its `knowledge/` links resolve.
3. Dry-run the scaffold against `examples/redfish/config.yaml` and confirm no `{{...}}`
   placeholder remains in the generated project.

## Version stamping

Follow the [shared Fiskwise version policy](https://github.com/DeepWaterIMR/fiskwise/blob/main/docs/VERSIONING.md).
Every ordinary authored commit increments the patch by 0.0.1 and stamps the current date. A
minor or major bump requires an explicit user request and `FISKWISE_VERSION_BUMP=minor|major`;
never choose one autonomously or create tags/releases automatically. Let `.githooks/pre-commit`
enforce the policy, preserve other custom hooks, and replay existing stamps unchanged during
merges or rebases. The hook also stamps the README version line.
