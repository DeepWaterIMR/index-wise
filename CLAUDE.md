# CLAUDE.md — index-wise (Claude Code)

This is the **Claude Code** pointer. The full agent contract is in
[`AGENTS.md`](AGENTS.md) — read it. This file only adds Claude-specific notes.

## What this repo is

A **knowledge pack** (like [BAIT](https://github.com/DeepWaterIMR/BAIT)) that teaches an
agent to build a **sdmTMB survey index** for a species and **generates a new project folder**
for it. It is installed once per machine; its skills live in `~/.claude/skills/` as
`index-*`. It is **public — never commit data or private paths here.** See the privacy
section of [`AGENTS.md`](AGENTS.md).

index-wise is part of the [Fiskwise ecosystem](https://deepwaterimr.github.io/fiskwise/),
alongside [BAIT](https://github.com/DeepWaterIMR/BAIT),
[wise-writing](https://github.com/DeepWaterIMR/wise-writing),
[spict-wise](https://github.com/DeepWaterIMR/spict-wise), and
[wise-presentations](https://github.com/DeepWaterIMR/wise-presentations). Follow each
project's own skills and routing guidance for its workflow.

index-wise owns sdmTMB index methods and scaffolding; BAIT owns Biotic access/privacy; and
wise-writing owns shared scientific style, package-loading, and generic reporting. Use
**`r-code-style`** for every managed R task. Install shared packs on demand; standalone
index-wise use does not require the Fiskwise coordinator. In managed mode, follow
`fiskwise-install`, `fiskwise-update`, or `fiskwise-uninstall`, honor saved R-install consent,
disabled toggles, and `renv.lock`, and do not repeat dependency updates. Database refresh stays
a separate opt-in BAIT action. Use `fiskwise-workflow` to route requests spanning packs.

## Where things are

- **Skills** — `skills/index-*/SKILL.md`. Installed globally by `skills/index-install`.
- **Shared knowledge** — `knowledge/*.md` (the method, filtering, sdmTMB, helpers, packages,
  project structure, rendering).
- **Project skeleton** — `project-template/`, copied and stamped by `scaffold.R` for each new
  species project.
- **Worked example** — `examples/redfish/`.

## Claude-specific notes

- **Project memory, not local memory.** When working *inside a generated project*, use that
  project's `ai/memory/` folder as your project memory (read `ai/memory/MEMORY.md` first, write new
  memory files there). Do **not** use `~/.claude/projects/.../memory/` for project facts —
  that folder is only for user-level preferences/identity.
- **Skills** — when the user types `/index-...` or asks to build/validate/report an index,
  invoke the matching skill. When they ask for Biotic data access, defer to BAIT's `biotic-*`
  skills.
- **Plan mode** — after the questionnaire in `index-new-project`, use plan mode to confirm
  the approach before scaffolding and rendering.
- **Code review before render** — Quarto renders are slow; review changed chunks and fix issues
  before starting a render. `/code-review` is optional where available. See `knowledge/rendering.md`.
- **R code style** — use the installed `r-code-style` skill for all R changes in managed work.

For everything else, see [`AGENTS.md`](AGENTS.md).

## Fiskwise version policy

Follow the [shared version policy](https://github.com/DeepWaterIMR/fiskwise/blob/main/docs/VERSIONING.md).
Every ordinary authored commit increments the patch by 0.0.1 and stamps the current date
(`VERSION` for knowledge packs; `DESCRIPTION` `Version` and `Date` for R packages).
Only an explicit user request may set `FISKWISE_VERSION_BUMP=minor|major`. Never choose one
autonomously or create tags/releases automatically. Let `.githooks/pre-commit` enforce the
policy, preserve other custom hooks, and replay existing stamps unchanged during merges or
rebases.

## wise-writing contract

For every generated project artifact, use `r-code-style` for managed R work and read the
installed `academic-style`, `academic-conventions`, and `academic-data-report` skills.
index-wise supplies the scientific workflow; wise-writing supplies shared style, package
loading, and publishing conventions. Install/update wise-writing on demand when needed.
Follow index-wise's `knowledge/wise-writing.md`. The workflow QMDs are HTML data
reports under `docs/data-report/`; shared assets belong in `docs/assets/`, project memory in
`ai/memory/`, tests in `ai/tests/`, and reviews in `ai/review/`.
