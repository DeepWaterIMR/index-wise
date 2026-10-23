[![Part of the Fiskwise ecosystem](https://deepwaterimr.github.io/fiskwise/assets/part-of-fiskwise.svg)](https://deepwaterimr.github.io/fiskwise/)

# 📈 index-wise — Build sdmTMB survey indices with AI agents

<!-- version -->
**Version 0.2.0** (2026-09-09)
<!-- /version -->

**Teach your AI coding agent to build a spatiotemporal survey index for stock assessment — for any species, on your own machine.**

index-wise is a knowledge pack that turns a general coding agent (Claude Code, Codex, Cursor, Gemini CLI, Mistral, …) into a competent assistant for building [**sdmTMB**](https://sdmtmb.github.io/sdmTMB/) (Anderson et al., 2025) survey indices from IMR bottom-trawl data, reproducing the method of [Vihtakari et al. (2026, ICES Journal of Marine Science)](https://doi.org/10.1093/icesjms/fsag009).

Tell your agent which species you want an index for, and it will:

1. **Ask you a short, structured questionnaire** and confirm a plan.
2. **Scaffold a new project folder** with a standard structure following wise-writing (`docs/`, `data/`, `R/`, `figures/`, `ai/`, `logs/`, `config/`).
3. **Compile the data** from the IMR Biotic database (and, optionally, legacy SPD files), applying the filtering that makes catches quantitative.
4. **Fit, validate, and report** an sdmTMB index, using helpers from [sdmTMBexperiments](https://github.com/DeepWaterIMR/sdmTMBexperiments) and maps from [ggOceanMaps](https://mikkovihtakari.github.io/ggOceanMaps/).

> **It is not a trained model.** Your data never leaves your machine and never enters any model's weights. The agent simply *reads this repo* while it helps you. See [Privacy](#-privacy-first).

## 🧰 Built on BAIT

index-wise sits **on top of** [BAIT](https://github.com/DeepWaterIMR/BAIT) (the Biotic AI Toolkit). BAIT handles Biotic **data access, the database, privacy, maps, and life-history**; index-wise adds the **sdmTMB index-building** layer. If BAIT is not installed yet, install it first:

```
install https://github.com/DeepWaterIMR/BAIT
```

## 🔒 Privacy first

This repo is **public and contains instructions only — never data**:

- **No data and no private paths** are ever committed here. Real data and paths live only in the *project folder the agent generates for you*, where `data/`, `logs/`, and `ai/review/` are git-ignored.
- The Biotic database lives **outside** any repo (BAIT default: `~/IMR_biotic_BES_database/`).
- During setup, **turn off model training / data retention** for your agent once — BAIT walks you through it and records the onboarding.

## 🚀 Quickstart

1. **Install BAIT** (if you haven't): `install https://github.com/DeepWaterIMR/BAIT`.
2. **Install index-wise:**
   ```
   install https://github.com/DeepWaterIMR/index-wise
   ```
   The agent runs [`index-install`](skills/index-install/SKILL.md): a privacy check → cloning index-wise → installing the skills globally → verifying BAIT and the R packages (`sdmTMB`, `sdmTMBexperiments`, `ggOceanMaps`).
3. **Start a species index:**
   ```
   Let's make a biomass index for snabeluer (beaked redfish) using all bottom trawl data
   collected during surveys, using index-wise.
   ```
   The agent runs the questionnaire, plans, scaffolds a project, and drives the four-step workflow.

## 🗺️ The four-step workflow

| Step | Skill |
|------|-------|
| Scaffold a project (questionnaire + plan) | [`index-new-project`](skills/index-new-project/SKILL.md) |
| Create valid study-region polygons | [`index-make-regions`](skills/index-make-regions/SKILL.md) |
| **1.** Compile & report the data | [`index-compile-data`](skills/index-compile-data/SKILL.md) |
| **2.** Fit the first feasible model | [`index-fit-model`](skills/index-fit-model/SKILL.md) |
| **3.** Validate / select the model | [`index-validate-model`](skills/index-validate-model/SKILL.md) |
| **4.** Final report + extensions | [`index-final-report`](skills/index-final-report/SKILL.md) |

Each step's document lives in [`project-template/docs/`](project-template/docs/) and is index-wise's own, evolving implementation — improve it directly as the routine matures. [`knowledge/workflow.md`](knowledge/workflow.md) points to the (IMR-internal) background material the method was originally distilled from, if you want the history.

Long renders are compiled with [`index-render`](skills/index-render/SKILL.md) in a screen session with a log in `logs/`.

## 📚 What's in this repo

- [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) — the agent contract.
- [`skills/`](skills/) — the `index-*` skills (installed globally).
- [`knowledge/`](knowledge/) — the shared source of truth (method, data filtering, sdmTMB, helpers, model selection, packages, project structure, rendering).
- [`project-template/`](project-template/) — the skeleton copied into each new project.
- [`scaffold.R`](scaffold.R) — stamps a project from `config.yaml`.
- [`examples/redfish/`](examples/redfish/) — a worked example.

## 🧰 Siblings

- [**BAIT**](https://github.com/DeepWaterIMR/BAIT) — IMR Biotic data access, the database, privacy, maps, life history. **Required.**
- [**wise-writing**](https://github.com/DeepWaterIMR/wise-writing) — the writing style, the document conventions, and the project skeleton this pack's scaffolder builds on. **Required for report generation.**
- [**spict-wise**](https://github.com/DeepWaterIMR/spict-wise) — SPiCT biomass-dynamic stock assessments. **The index this pack exports is what a SPiCT assessment consumes**; step 4's selected index becomes SPiCT's `obsI`.
- [**wise-presentations**](https://github.com/DeepWaterIMR/wise-presentations) — Quarto RevealJS slides.

## 🚨 You are still in charge

This repo is designed to create a survey index template. It speeds up the data and model compilation, but does not create ready indices for assessment. It provides a place to start, not a final deliverable. Expert judgment is required for the final assessment.

## 📖 References

Anderson, S.C., Ward, E.J., English, P.A., Barnett, L.A.K., & Thorson, J.T. (2025). sdmTMB: An R Package for Fast, Flexible, and User-Friendly Generalized Linear Mixed Effects Models with Spatial and Spatiotemporal Random Fields. Journal of Statistical Software, 115(2), 1–46. [doi:10.18637/jss.v115.i02](https://doi.org/10.18637/jss.v115.i02).

Vihtakari, M., Aune, M., Assmann, K.M., Howell, D., Hallfredsson, E.H., & Ward, E.J. (2026). *Demersal distribution and fisheries independent trends of beaked and golden redfish in the Barents and Norwegian Seas.* ICES Journal of Marine Science, 83(2), fsag009. [doi:10.1093/icesjms/fsag009](https://doi.org/10.1093/icesjms/fsag009).



## wise-writing compatibility

New projects use wise-writing's folder structure and HTML data-report conventions.
Read [the shared contract](knowledge/wise-writing.md) and
[the generated layout](knowledge/project-structure.md). Supply confirmed `AUTHORS` and
`AFFILIATIONS` in the scaffold configuration. Existing species projects are not migrated
automatically. The installed wise-writing skills govern all generated artifacts.

Run `Rscript config/validate-scaffold.R` to check a synthetic scaffold without accessing data
or fitting models. Add `--render` to render a small synthetic report using the same metadata,
assets, citation helper, and code-fold settings.
