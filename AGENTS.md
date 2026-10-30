# AGENTS.md — index-wise

You are helping a scientist build a **spatiotemporal survey index** with
[**sdmTMB**](https://github.com/sdmTMB/sdmTMB) for stock assessment, reproducing the method
of **Vihtakari et al. (2026)**, *ICES Journal of Marine Science*
([doi:10.1093/icesjms/fsag009](https://doi.org/10.1093/icesjms/fsag009)). You write **R**
with **tidyverse** syntax; figures with **ggplot2**, maps with
[**ggOceanMaps**](https://mikkovihtakari.github.io/ggOceanMaps/), and index-specific helpers
from [**sdmTMBexperiments**](https://github.com/DeepWaterIMR/sdmTMBexperiments).

> This is the entry point for **Codex, Cursor, Gemini CLI, Mistral, and other agents**.
> Claude Code reads the equivalent pointer in [`CLAUDE.md`](CLAUDE.md). Keep substantive
> guidance in sync while preserving agent-specific setup notes.

---

## What index-wise is

A **vendor-neutral knowledge pack** — not a trained model, not a repo you fill in place. It
teaches an agent to build a survey index for a chosen species, and it **generates a new
project folder** for that species. You learn the method by *reading this repo at runtime*.

The method works for any bottom-trawl survey. The default data source is the Institute of
Marine Research (IMR) Biotic database through [BAIT](https://github.com/DeepWaterIMR/BAIT)
(the Biotic AI Toolkit), which handles Biotic **data access, privacy, maps, and life history**
through its `biotic-*` skills. BAIT is needed only for Step 1 with Biotic data; install it then
(`install https://github.com/DeepWaterIMR/BAIT`). Users with other survey data enter at Step 2
with a station table that meets the own-data contract in `knowledge/data-filtering.md`.

index-wise is part of the [Fiskwise ecosystem](https://deepwaterimr.github.io/fiskwise/),
alongside [BAIT](https://github.com/DeepWaterIMR/BAIT),
[wise-writing](https://github.com/DeepWaterIMR/wise-writing),
[spict-wise](https://github.com/DeepWaterIMR/spict-wise), and
[wise-presentations](https://github.com/DeepWaterIMR/wise-presentations). Follow each
project's own skills and routing guidance for its workflow.

### Pack boundaries and shared skills

index-wise owns the sdmTMB survey-index method and the species-project scaffold. BAIT owns
Biotic data access and privacy; wise-writing owns shared scientific style, package-loading,
project layout, and generic reporting. Keep index-wise installable on its own and obtain shared
dependencies on demand when the requested work needs them; the Fiskwise coordinator is
optional.

Use the installed **`r-code-style`** skill for every managed R task. In managed mode, follow
`fiskwise-install`, `fiskwise-update`, or `fiskwise-uninstall` and do not repeat clone, skill
registration, or dependency steps. Honor saved R-install consent and disabled install toggles.
Use `fiskwise-workflow` to route requests spanning packs.
A project with `renv.lock` is controlled by renv; inspect and report missing packages rather
than installing or updating them outside renv. Never refresh the Biotic database as part of an
index-wise install or update; that is a separate opt-in BAIT action.

---

## ⛔ PRIVACY — non-negotiable, keep in mind on every task

Biotic data is confidential and some of it is sensitive. **This repo is public and must
contain no data and no private information.**

1. **Never commit data or private paths into index-wise.** No raw records, no BES
   database paths, no local absolute paths (`/Users/...`, `OneDrive`, `CloudStorage`), no
   station coordinates. Templates use **placeholders and code**, never data.
2. Real paths and real data only ever live in the **generated project folder**, which is the
   user's own repo — and even there, `data/`, `logs/`, and `ai/review/` are git-ignored.
3. **Reuse BAIT's privacy gate for Biotic data.** Model-training/data-retention is a one-time onboarding
   check recorded in `~/.bait/config.json` (`privacy_onboarded_at`). If that marker exists,
   do **not** re-gate routine local work. See BAIT's `skills/biotic-privacy/SKILL.md`.
4. **Default to derived outputs.** Aggregates, model parameters, indices, and figures are
   generally shareable; raw records and precise positions are not.

If a request would breach any of the above, stop and explain rather than comply.

---

## Working across projects (important)

index-wise is meant to be installed **once per machine** (BAIT-style) and used to spin up
**many** species projects — not cloned into each repo. When set up via `index-install`, its
location is saved to `~/.index-wise/config.json` and its `index-*` skills are linked into the
agent's user-level skills folder (`~/.claude/skills/` for Claude Code,
`~/.agents/skills/` for Codex).

- **Trigger:** the user asks to *"make a biomass/abundance index for `<species>` using
  index-wise"*, or to build/validate/report an sdmTMB survey index.
- **If index-wise isn't installed yet** (e.g. *"install
  https://github.com/DeepWaterIMR/index-wise"*), run `skills/index-install/SKILL.md`
  first.
- **Never install at a filesystem root / system directory.** Refuse and suggest a safe
  user-space location.

---

## How to work — capability router

The workflow has **four steps**, each with a skill. Read the skill's `SKILL.md` (which links
into `knowledge/`) before acting.

| If the user wants to…                                        | Read |
|--------------------------------------------------------------|------|
| Install / set up index-wise                              | `skills/index-install/SKILL.md` |
| Update it (git pull + re-sync skills)                        | `skills/index-update/SKILL.md` |
| Create / validate study-region polygons                       | `skills/index-make-regions/SKILL.md` |
| Any sdmTMB index question, in any project layout             | `skills/index-sdmtmb/SKILL.md` |
| **Start** a new species index (questionnaire → scaffold)     | `skills/index-new-project/SKILL.md` |
| **Step 1** — compile & report the data                       | `skills/index-compile-data/SKILL.md` |
| **Step 2** — fit the first feasible model                    | `skills/index-fit-model/SKILL.md` |
| **Step 3** — validate / select the model                     | `skills/index-validate-model/SKILL.md` |
| **Step 4** — final report + extensions, export the index     | `skills/index-final-report/SKILL.md` |
| Render long Quarto docs (screen session, logs, toggles)      | `skills/index-render/SKILL.md` |

Shared knowledge lives in `knowledge/`:

- `workflow.md` — the four steps and the reference documents each is modelled on.
- `data-filtering.md` — **the critical filtering logic** (gear condition, sample quality,
  station type, duplicates, swept-area density). Reproduce it exactly.
- `sdmtmb.md` — sdmTMB essentials (mesh, families, spatial/spatiotemporal, predict,
  get_index, offset).
- `sdmtmbexperiments.md` — the helper-function catalogue and conventions.
- `model-selection.md` — **the comparability contract** for Step 3: identical records, when
  AIC is and is not comparable, per-observation hold-out likelihood, the selection stages,
  AIC-then-CV cost control, and how to report a carried-forward model that is not the winner.
- `packages.md` — the package ecosystem and install lines.
- `project-structure.md` — the structure of the generated project folder.
- `rendering.md` — Quarto rendering, screen sessions, logs, toggles, figure formats.

---

## Golden rules for building an index

1. **Read the method first.** Before writing model code, read `knowledge/sdmtmb.md`,
   `knowledge/sdmtmbexperiments.md`, and the sdmTMB docs
   (<https://pbs-assess.github.io/sdmTMB/>). Don't guess the API.
2. **Use the helpers, don't reinvent them.** Meshes, prediction grids, comparisons, retros,
   CV, and maps come from `sdmTMBexperiments`; maps from `ggOceanMaps`. See
   `knowledge/sdmtmbexperiments.md`.
3. **Define sampling units and filter data correctly.** Quantitative density estimates require
   stable haul keys, resolved catchsample logic, true zeros, and documented `gearcondition`,
   `samplequality`, and `stationtype` rules. Follow `knowledge/data-filtering.md`; do not treat
   numeric quality codes as a universal ordinal scale.
4. **Start simple.** The first model has **no length groups** — confirm the method works,
   then extend. No temperature term by default.
5. **Keep selection comparable.** Candidates in a selection table must be fitted to identical
   records, only `comparable` rows may be compared, hold-out likelihood is reported per
   observation, and the winner is looked up in the metric column — never at row 1. See
   `knowledge/model-selection.md`; use `sdmTMBexperiments::sdmTMB_selection()` rather than a
   hand-rolled loop.
6. **Review before you render.** Quarto renders are slow. Review changed chunks/scripts and
   resolve issues before an expensive render. `/code-review` is optional where available.
7. **Run renders detached** with a log in `logs/`; screen/tmux are optional tools. Report the
   process/session and log location, and
   suggest running on a server. Once `data/output` files exist, flip the caching toggles to
   `FALSE` so re-renders load instead of refitting.
8. **Plan mode first.** After the questionnaire, present a plan and confirm before writing
   and compiling documents.

Use **`r-code-style`** for all R changes in managed projects; index-wise's method knowledge
does not replace the shared R coding guidance.

---

## Project memory (in the generated project)

Each generated project has a committed, shared `ai/memory/` folder. **Agents use that folder as
project memory — not the agent's local per-machine memory.** Read `ai/memory/MEMORY.md` (the
index) first; write a new markdown file with YAML frontmatter when you learn something
non-obvious, and add a one-line pointer to `MEMORY.md`. See the project's `ai/memory/README.md`.

---

## House style

- tidyverse, not base R, for data manipulation; `|>` or `%>%` (match the file you edit).
- Species use **Norwegian** `commonname` values (e.g. `"snabeluer"`, `"vanlig uer"`); confirm
  via BAIT's `taxaindex` lookup — don't hard-code from memory.
- **Coordinates in kilometres** for sdmTMB (`X`/`Y`); helpers multiply by
  `coord_multiplier = 1000` for CRS metres. Attach `library(sdmTMBexperiments)` so ggOceanMaps
  land data is available.
- **Do not hard-wrap prose** in `.qmd`/`.Rmd` files — write each paragraph as one line
  (soft-wrap editors). Code chunks follow normal formatting.
- **Raster figures**: `fig-format: jpeg`; keep rendered HTML as small as feasible.
- Comment density and naming match the surrounding file.

## wise-writing contract

For every generated project artifact, use `r-code-style` for managed R work and read the
installed `academic-style`, `academic-conventions`, and `academic-data-report` skills.
index-wise supplies the scientific workflow; wise-writing supplies shared style, package
loading, and publishing conventions. Install/update wise-writing on demand when those skills
are needed. Follow index-wise's `knowledge/wise-writing.md`. The workflow QMDs are HTML data
reports under `docs/data-report/`; shared assets belong in `docs/assets/`, project memory in
`ai/memory/`, tests in `ai/tests/`, and reviews in `ai/review/`.

## Fiskwise version policy

Follow the [shared version policy](https://github.com/DeepWaterIMR/fiskwise/blob/main/docs/VERSIONING.md).
Every ordinary authored commit increments the patch by 0.0.1 and stamps the current date
(`VERSION` for knowledge packs; `DESCRIPTION` `Version` and `Date` for R packages).
Only an explicit user request may set `FISKWISE_VERSION_BUMP=minor|major`. Never choose one
autonomously or create tags/releases automatically. Let `.githooks/pre-commit` enforce the
policy, preserve other custom hooks, and replay existing stamps unchanged during merges or
rebases.
