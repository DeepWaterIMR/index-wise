# AGENTS.md — {{SPECIES_NAME}} survey index

This project builds a **spatiotemporal sdmTMB survey index** for **{{SPECIES_NAME}}**
(*{{SPECIES_LATIN}}*) for stock assessment, using the method of Vihtakari et al. (2026,
ICES JMS). It was scaffolded from
[index-wise](https://github.com/DeepWaterIMR/index-wise).

> Codex, Cursor, Gemini CLI, Mistral, and other agents read this file. Claude Code reads
> [`CLAUDE.md`](CLAUDE.md).

## The method lives in index-wise

The *how* — data filtering, sdmTMB usage, the helper functions, the four-step workflow,
rendering discipline — is documented in the installed **index-wise** knowledge pack and
its `index-*` skills. **Read those; don't re-derive the method here.** Data access comes from
**BAIT** (`biotic-*` skills). If either is missing, install it (`install
https://github.com/DeepWaterIMR/index-wise`).

## This project's rules

1. **`config.yaml` is the single source of truth.** Species, surveys, response, length
   groups, CRS, map display settings, grid size, mesh cutoff, gear-width policy, and the selected
   index all live there and are read at run time by `R/0_setup.R`. Don't hard-code them in the qmds.
2. **No data or private paths in tracked files.** `data/`, `logs/`, and `ai/review/` are
   git-ignored. Real GIS polygons and data extracts go in `data/source/` only.
3. **Define sampling units and filter correctly.** Follow index-wise's
   `data-filtering.md` for stable haul keys, catchsample aggregation, survey-specific
   `gearcondition`, conditional `samplequality`, `stationtype`, duplicate diagnostics, true
   zeros, and swept-area density. Do not infer code meanings from their numeric order.
4. **Start simple.** First model has no length groups and no temperature term.
5. **Step 1 roles are distinct.** `compile-data.qmd` is survey selection and coverage;
   `<species>-<region>-data-report.qmd` is the compiled station/response report and owns length
   products and diagnostics. Do not duplicate length-allocation material in survey selection.
6. **Document provenance is explicit.** Keep the `published-title: "Version"` date label and the
   index-wise/researcher-supervised-AI provenance statement in every main report; add project-specific authors and affiliations in their YAML headers.
7. **Review before you render.** Renders are slow — code-review changed chunks and fix issues
   first, then render in a screen session with a log in `logs/` (index-wise `index-render`
   skill). Flip compute toggles to `FALSE` once `data/output/` files exist.

## Workflow

| Step | Document(s) | index-wise skill |
|---|---|---|
| 1. Compile & report data | `docs/data-report/survey-selection/compile-data.qmd`, `docs/data-report/data-overview/{{SPECIES_SLUG}}-{{REGION_SLUG}}-data-report.qmd` | `index-compile-data` |
| 2. Fit first model | `docs/data-report/fit/fit.qmd` | `index-fit-model` |
| 3. Validate / select | `docs/data-report/validation/validate.qmd` | `index-validate-model` |
| 4. Final report + export | `docs/data-report/{{SPECIES_SLUG}}/report.qmd` (+ `*-section.qmd`) | `index-final-report` |

Full rebuild: `Rscript docs/render.R` (slow — see the rendering rules).

## Project memory

Read [`ai/memory/MEMORY.md`](ai/memory/MEMORY.md) first. Record non-obvious decisions as new memory
files here (this shared `ai/memory/` folder — **not** your local per-machine memory) and add a
pointer to `MEMORY.md`. The questionnaire answers are in `ai/memory/scaffold-interview.md`.

## House style

tidyverse; coordinates in km for sdmTMB; attach `library(sdmTMBexperiments)`; **do not
hard-wrap prose** in qmd files; raster figures `fig-format: jpeg`; keep HTML small.

## wise-writing contract

For every generated project artifact, read the installed `academic-style`,
`academic-conventions`, and `academic-data-report` skills. index-wise supplies the
scientific workflow; wise-writing supplies structure, style, and publishing conventions.
Follow index-wise's `knowledge/wise-writing.md`. The workflow QMDs are HTML data
reports under `docs/data-report/`; shared assets belong in `docs/assets/`, project memory in
`ai/memory/`, tests in `ai/tests/`, and reviews in `ai/review/`.
