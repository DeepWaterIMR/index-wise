---
name: index-new-project
description: Start a new sdmTMB survey-index project for a species — run the structured questionnaire, confirm a plan, then scaffold a new project folder from project-template with config.yaml. Use when the user says "make a biomass/abundance index for <species> using index-wise", or asks to start/scaffold a new survey index.
---

<!-- pack-resources:start -->
**Pack resources:** resolve `index-wise` from `~/.index-wise/config.json` → `index_template_path` (or
`~/.fiskwise/config.json` → `components.index-wise.path`). If neither exists, use the
checkout containing this skill, or locate/obtain the pack through its install instructions.
Paths such as `knowledge/`, `cookbook/`, `config/` and `project-template/` belong to that
repository, not the current research directory. For a copied skill, resolve a link that
leaves this skill's directory against the corresponding source skill under that root;
keep bundled `references/` links relative to the skill. Never assume `../../` from an
agent's global skills folder reaches the repository. Use absolute resolved script paths.
<!-- pack-resources:end -->


# Start a new index project

Goal: turn *"make a biomass index for `<species>` using all bottom trawl survey data"* into a
scaffolded project ready for the four-step workflow. **Ask the questionnaire, plan, then
scaffold — do not start writing model code yet.**

Read `knowledge/workflow.md` and `knowledge/project-structure.md` first.

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Step 1 — The questionnaire (ask; don't assume)

Confirm the species name via BAIT's `taxaindex` lookup, then ask the questions below. Group
them; offer sensible defaults; but **get real answers** — these drive the whole project. Record
every answer for `ai/memory/scaffold-interview.md`.

1. **Species** — Norwegian `commonname`(s) for `filter_sp` (confirm via BAIT `taxaindex`),
   plus scientific name and a display name/slug.
2. **Surveys and cruise series** — which individual surveys provide bottom-trawl data **with true
   absences**? Include/exclude rules. (List candidates from the database via BAIT.)
3. **Distribution & SPD** — is the species northern/offshore or **southern/coastal**? For
   southern/coastal species, SPD files add little — **suggest BES only** (`USE_SPD: false`).
4. **Gear width** — default to a common 25 m effective width for all trawls. If multiple gears
   are represented, keep `geartype` as a fixed effect; revert to gear-specific widths only when
   diagnostics justify the extra complexity.
5. **Response & length groups** — biomass or abundance density? Which products: total biomass,
   over-X-cm biomass (what threshold?), length-group abundances (which breaks)?
6. **Assessment model** — what consumes the index (e.g. SPiCT)? This drives the
   spatiotemporal/year-effect choice for the selected index (AR1 + no year effect for total/
   length; IID + year fixed effect for the assessment-selected index).
7. **Years** — first year to include (default `> 1980`).
8. **Domain** — study area / prediction region, CRS (EPSG), grid cell size (km), mesh cutoff
   (km), barrier mesh yes/no. GIS polygons are **user-supplied** and go in the project's
   `data/source/` — never in the template.
9. **Russian data** — included by default; ask only if they want to exclude it.
10. **Human metadata** — accountable authors and affiliations using wise-writing's
    `AUTHORS` and `AFFILIATIONS` schema; confirm exact AI models and roles before reporting.
11. **Outputs** — which are official vs exploratory vs draft?

## Step 2 — Plan (plan mode)

Summarise the answers, the resulting `config.yaml`, the documents to be created, and the order
of work. **Confirm with the user before scaffolding.** Flag anything ambiguous (e.g. the
gear-width/geartype-covariate implication, or AR1 vs IID for the selected index).

## Step 3 — Scaffold

1. Choose a target directory for the new project (ask the user; a sibling of the current repo
   is typical). Never scaffold at a system root.
2. Write `config.yaml` values from the answers (see fields in `knowledge/project-structure.md`).
3. Run `scaffold.R` from the index-wise install:

   ```r
   source("<index_template_path>/scaffold.R")
   scaffold_index(config = "config.yaml", target = "<target-dir>")   # dry = TRUE to preview
   ```

   This copies `project-template/` into the target and stamps every `{{PLACEHOLDER}}`. Confirm
   no `{{...}}` remains afterwards.

4. Initialize local Git in the new project if needed, with no remote. Commit or push only
   when authorized by the user. Keep the scaffolded `VERSION` and `.here` files.

## Step 4 — Seed project memory

In the new project's `ai/memory/`:
- Write `scaffold-interview.md` with the full Q&A (frontmatter `type: project`).
- Update `MEMORY.md` with a one-line pointer.
- Note any decisions still open in `workflow.md`.

## Done

Tell the user the project is scaffolded and what's next: **Step 1 — compile the data**
(`index-compile-data`), which needs a local BES database and IMR intranet. Remind them the
generated project's `ai/memory/` is the shared project memory to use from now on.
