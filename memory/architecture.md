---
name: architecture
description: How index-template is organised and the key design decisions.
metadata:
  type: project
  author: claude
  created: 2026-07-02
---

# Architecture

index-template is a **BAIT-style vendor-neutral knowledge pack + generator**, decided with the
user (not a clone-and-fill repo).

- **Installed once per machine**; `index-*` skills copied to `~/.claude/skills` and
  `~/.codex/skills`. Install path recorded in `~/.index-template/config.json`.
- **Sits on top of BAIT** — BAIT owns Biotic data access/privacy/maps/life-history
  (`biotic-*`); index-template adds the sdmTMB index layer. It reuses BAIT's privacy gate
  (`~/.bait/config.json`), it does not define its own.
- **Generates a separate project folder** per species via `scaffold.R` + `project-template/`.
  Delivery model = generator; scaffolding = hybrid (config stamps identity/paths, agent adapts
  analytical qmd content).

Layout: `AGENTS.md`/`CLAUDE.md` (contract), `skills/index-*` (9 skills), `knowledge/*.md`
(9 shared-truth files), `project-template/` (skeleton), `scaffold.R`, `examples/redfish/`,
`cookbook/`, `memory/`.

**Step 3 is a comparability contract, not a pile of function calls.** `knowledge/model-
selection.md` is the method: candidates fitted to identical records, only `comparable` rows
compared, hold-out likelihood per observation rather than summed, `sanity()` reported but not
gating, AIC ladder first with cross-validation on an AIC-ranked shortlist, the winner looked up
in the metric column rather than at row 1, and the gap stated whenever the carried-forward model
is not the winner. The mechanics live in `sdmTMBexperiments::sdmTMB_selection()` +
`selection_frame()` / `best_candidate()` / `sdmTMB_cv_summary()` / `add_aic_weights()`, added
there rather than here (see the boundary rule below); `project-template/R/0_setup.R` carries
only the two project-side conveniences, `drop_one_candidates()` and `selection_kable()`.

**Boundary:** call generic helpers from `sdmTMBexperiments`; never duplicate package internals
here. Reference data (species/surveys/gear) comes from the Biotic database via BAIT.

**Scaffold mechanics:** only identity tokens (`{{SPECIES_NAME/SLUG/LATIN}}`) are stamped;
every analytical setting lives in `config.yaml` and is read at run time by
`project-template/R/0_setup.R`. Files named `STOCK-*` and the `sdmtmb/STOCK/` folder are
written once per stock (`SPECIES_SETTINGS` keys, or `STOCK_SLUG`), each stamped with that
stock's identity (since 0.2.5x; see [[third-project-lessons]]).

Related: [[reference-sources]], [[conventions]].
