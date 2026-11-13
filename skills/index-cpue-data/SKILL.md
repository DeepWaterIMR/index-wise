---
name: index-cpue-data
description: Prepare commercial catch-and-effort data (ERS electronic logbooks, aggregated logbooks or sales notes) for a standardised CPUE index — map the extract to the record schema, reconcile with landings, resolve vessel identity, apply the documented filter cascade and core-fleet thresholds, and explore effort, fleet composition and spatial coverage. Use when the user asks for a CPUE, LPUE or commercial (logbook) index, or to prepare or check logbook data for one.
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


# CPUE step 1 — records

Goal: one clean record frame of the fleet, gear and area the index describes, with every
exclusion logged. **Read `knowledge/cpue.md` in full first**: it explains why CPUE is not
abundance and which data decisions bias it.

**Data access.** Logbooks and sales notes come from the Directorate of Fisheries through IMR's
internal data services, **not** from the Biotic database (BAIT does not cover them). Ask the
user where their extract is.

**Bespoke treatment, every time.** Commercial data differ by source, country, period and
fishery in what their fields mean, so there is no generic reader: write and document the data
treatment for this extract (`knowledge/cpue.md`, *Every commercial dataset needs its own
treatment*). Never reuse another stock's or country's treatment unchecked. Record-level data (vessels, positions, catches) are confidential:
keep them in the project's git-ignored `data/source/cpue/`, show only aggregates (no individual
vessels, positions aggregated to cells), and commit no data or private paths.

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Ask first

1. **Source and unit** — ERS hauls, aggregated logbooks (day/trip) or sales notes (trip)? Did the
   source change during the series (e.g. paper logbooks → ERS)? One unit per index.
2. **Fishery** — target species, gear, area, season; which vessels (all, ≥ a length)?
3. **Effort** — what the effort and duration fields measure in this fishery (traps per haul, soak
   or only hauling time, tow time). Read the reporting instructions; name variables after what
   they are.
4. **Breaks** — management or fleet changes (quota systems, individual vessel quotas, closures,
   minimum size, new vessels) with their years.
5. **Landings** — a landings table for the reconciliation.

Record the answers in the project's `ai/memory/`.

## Work in `docs/sdmtmb/cpue/cpue.qmd` (data sections)

If the project was scaffolded before the CPUE document existed, copy
`project-template/docs/sdmtmb/cpue/cpue.qmd` and `project-template/R/cpue_helpers.R` into it
and add the `CPUE:` block of `project-template/config.yaml`.

1. **Map** the extract to the schema in the `load` chunk (`year`, `month`, `yday`, `vessel_id`,
   `vessel_length`, `catch`, `effort`, `lon`, `lat`, `depth`, optional `soak`, `gear_spec`,
   `area`). Choose the position closest to where the gear fished (stop position, matched gear or
   VMS positions) and state the rule.
2. **Reconcile** logbook catch with landings per year (`cpue_reconcile()`); report coverage.
3. **Vessel identity** — `cpue_vessel_changes()` splits a vessel replaced under the same
   identifier; `cpue_vessel_activity()` adds years active and records per vessel.
4. **Filter cascade** — plausible ranges and core-fleet thresholds from `config.yaml`
   (`CPUE: ranges`, `min_years_active`, `min_records_year`, `min_records_total`) through
   `cpue_filter_cascade()`; the table reports records, vessels and catch after each step. Look
   for unit errors (grams for kilograms) in the steps that remove much catch with few records.
5. **Explore** — records and vessels per year, fleet by years active, catch against effort
   (log scales; slope ≈ 1 → offset, < 1 → covariate), season, depth (from bathymetry when the
   logbook field is missing or zero), positions aggregated to cells per year. Flag covariates
   that trend with time by construction (experience in the fishery).
6. **Terminal year** — how complete is it? Note the month the data end (`CPUE: final_month`).

## Before the model

Code-review the mapping and filter chunks, then render the data sections (`index-render`).
Write a memory note with the source, unit, filters and their effect, the coverage and every
known break. Then continue with `index-cpue-model`.
