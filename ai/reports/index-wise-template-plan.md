# Plan: a benchmark-index template for index-wise, from the ling/tusk project

Status: draft for the maintainer's review (2026-11-25). Nothing is implemented. Written by
Claude Opus 5.5 (Anthropic) from a read-only review; the maintainer decides.

Source project: `lotidae-assessment-index` (ling `lin.27.1-2` and tusk `usk.27.1-2`, ICES 1–2,
WKBMSYSPiCT5), 92 commits from the index-wise 0.2.x scaffold (2026-11-05) to the unattended
pipeline (2026-11-25), and its `ai/memory/` (19 files). Compared against index-wise 0.2.48
(`main` 356a3ac), hpc-wise `knowledge/`, and Fiskwise `docs/VERSIONING.md` and
`docs/AI-DISCLOSURE.md`.

Goal: a request such as *"make survey indices for <stock(s)> for benchmark <X>"* should give,
from the template, the same kind of outcome as this project: data documents, first fit, staged
model selection, final report with diagnostics, sensitivity and influence sections, summary,
assessment hand-off, and an unattended server pipeline.

## 1. Headline recommendations

1. **One code path for one or many stocks.** Make `SPECIES_SETTINGS` the only config shape
   (a single-stock project is the N = 1 case), with per-stock files named `<sp>-N-*.qmd`
   generated from one master document per step by a generalised parity script. This is the
   pattern that held up in the project; Quarto `params` rendering of one file per species was
   not tried and would clash with per-document `_files` and cache folders.
2. **Move model selection out of the document.** The template's `validate.qmd` runs
   `sdmTMB_selection()` inside the render; the project replaced that with a per-candidate stage
   runner (`R/validation/`) whose caches the document only reads. This is the largest gap and
   the change that made 10–15 h renders, server crashes and Sigma2 possible. Port it as the
   template's Step 3, with candidate lists and tolerances in a `SELECTION:` config block.
3. **Port the unattended pipeline** (`R/run_models.sh` → selection → `sync_final_model.R` →
   `R/report/run_report.sh` → report → summary) with resumable done-flags, the
   specification stamp check, and a documented cache inventory. Make the order of actions a
   knowledge file, not only project memory.
4. **Strip the survey names out of the report code.** In the project, `run_report_surveys()`,
   the `coastal-sq2` and `major-series` sensitivities and the product names are hard-coded for
   this stock; the template already reads `REPORT_SURVEYS`, so port onto that and add
   `SENSITIVITIES:` and `PRODUCTS:` config blocks.
5. **Write the method lessons into knowledge before touching code** (phase A below): trend not
   level and the reference month; CV block size from the Matérn range with block-level SE;
   decision rules per stage; cache-hash and version pitfalls; mission-level survey
   qualification; render and pipeline discipline. These are cheap, low-risk and already
   stale in two places (§3.1).
6. **Leave HPC mechanics in hpc-wise.** Most Sigma2 findings are already in hpc-wise
   `knowledge/sigma2-olivia.md` and `estimation.md`; index-wise should ship only the
   selection-specific job scripts and point to hpc-wise for the driver, modules and billing.
7. **Test the template, not just the scaffold.** Add synthetic tests for the stage decision
   rules, the config sync round-trip, the parity generator for N stocks, and a `SMOKE=1` stage
   run on simulated data, run by `config/validate-scaffold.R` and CI.

## 2. What the project has that the template lacks

Legend: **G** generalise into the template, **K** lesson for knowledge/skills, **P** stays
project-specific, **U** belongs upstream (another repository).

### 2.1 Project shape

| Piece in the project | Template today | Action |
|---|---|---|
| Two species from one config (`SPECIES_SETTINGS` merged over shared keys by `R/0_setup.R`, `index_species` set per document, `data/output/<sp>/`) | One species per project; "multiple species → one `docs/sdmtmb/<species>/` folder" is described but not implemented | **G** — always `SPECIES_SETTINGS`; flat legacy configs read as one species |
| Numbered documents 0–6 (`0-stock-background`, `<sp>-1-summary`, `-2-survey-selection`, `-3-data`, `<sp>-4-fit`, `<sp>-5-validate`, `<sp>-6-report`) | Data documents numbered 1–3; `fit.qmd`, `validate.qmd`, `SPECIES/report.qmd` unnumbered | **G** — number all documents; reading order = number |
| Twin documents + `ai/tests/test-species-parity.R write` | none | **G** — generalise to N stocks: first stock is the master, the others are written from it; allowed differences are the title, `index_species` and the fallback name |
| Shared report sections in `docs/benchmark/sdmtmb/sections/` | per-species `SPECIES/*-section.qmd` | **G** — shared `sections/`; per-stock folder holds only the report |
| `docs/benchmark/{assets,background,data,sdmtmb}` | already ported (`DOCS_DIR`, 0.2.31) | done |
| Summary rendered last from the report caches, with Limitations | `STOCK-1-summary.qmd` placeholders | **G** |
| Benchmark website (`publish-site.sh`, GitLab Pages) | none | **G, optional** — `SITE:` block (repo path, folder); off by default |
| Laptop (Biotic database, confidential data) vs server (fits, renders) split; rsync for `data/`, git deploy key for code | partly in hpc-wise `sync.md` | **K** — a "machines" question in the interview; pointer to hpc-wise |

### 2.2 Step 1 — data

| Piece | Template | Action |
|---|---|---|
| Mission-level survey qualification, never backfill a whole cruise series | in `data-filtering.md` and `compile_functions.R` | done; keep |
| Position errors (GEBCO), tow speed to NA, same-position hauls by vessel, data checks | ported in 0.2.2x | done |
| Prediction region per stock (`build_stock_region()`, buffer 100 km, `MAX_DEPTH` from the slope zeros) | ported | done; add the *why* of the buffer/depth choice to `regions.md` (**K**) |
| `FIRST_YEAR` set by regular coverage of the main stock area, not by the database's first year | not stated | **K** — interview question and `data-filtering.md` |
| Confidential subsets (`INCLUDE_RUSSIAN`, reference-fleet data used only for a threshold, never on disk) | `INCLUDE_RUSSIAN` exists; reference-fleet rule only in this project | **K** — `data-filtering.md`/BAIT pointer; the switch is generic |
| Fishable length from reference-fleet lengths (25 % of mode, 5 cm running mean; 50 % rule as sensitivity) | `fishable_length.R`, `FISHABLE_PROP` ported | done; add the sensitivity threshold key (`SENSITIVITY_OVER_CM`) (**G**) |
| Data-review additions (coverage maps by series, zero share by series, sample sizes series × year, length–weight by sex, confounding table series × quarter/trawl/depth) | partly | **G** — they answer the standard reviewer question "is the trend a survey-mix artefact?" |
| `SURVEY_NAMES` for surveys without a series code; series colours | colours generic | **P** values, **G** key |

### 2.3 Step 2 — first fit

| Piece | Template | Action |
|---|---|---|
| Three products (total IID + year, fishable IID + year, total AR1 without year) | single first model | **G** via `PRODUCTS:` |
| Per-stock `MONTH_TERM` (none/factor/smooth), `FISHABLE_YEAR_EFFECT`, `SMOOTHED_SPATIAL: off` | partly | **G** keys; **K** the diagnostics that chose them (`first-fit-diagnostics.md`: smooth collapsing to linear, AR1 ρ≈1 absorbing ω) |
| Base fit sets the CV block size (largest Matérn range of the total IID fit, rounded up to 50 km) | `cv_block_size()` ported | done; **K** "re-make folds when the model data change" |

### 2.4 Step 3 — staged selection (largest gap)

| Piece | Template | Action |
|---|---|---|
| Per-candidate runner: `stage_lib.R` (setup, candidates, `run_candidate()`, `read_stage()`, `assemble_stage()`, `decide_stage()`, `decide_smoothed()`, `assemble_mesh()`, `run_grid_stage()`), `run_candidate.R`, `assemble_stage.R`, `run_species.sh`, `smoke_test.R` | in-document `sdmTMB_selection()` | **G** — port; keep the document as a reader of `stage-<stage>.rds` |
| Stage order mesh → fields → geometry → fixed → family → grid, incoming/selected vocabulary, one-SE rule everywhere, Tweedie-first parsimony in family, fields restricted to IID + year for SPiCT with a separate smoothed-structure selection | `model-selection.md` has it; `workflow.md` and the validate skill description still list the old order | **K** fix the stale text; **G** the code |
| Block-level paired SE (`paired_se()`, `cv_groups()`) — 0–60 % larger than haul-level, changed no decision here | not ported | **G** + **K** |
| Mesh rule (best ELPD among sane cutoffs = reference; coarsest sane cutoff within 5 % on terminal/Δρ/MARD, every cutoff in between too), `MESH_LADDER_KM` per stock | rule in knowledge | **G** code (`assemble_mesh()`, `plot_mesh_selection()`) |
| Grid stage 5–200 km, coarsest within 1 % of the 5 km index | rule in knowledge | **G** code |
| Extra fixed-effect candidates: cruise series (`fsurvey`, predicted for `REFERENCE_SURVEY`), trawl-model group (`fgear`, `gear_model_group()`), quadratic depth | partly | **G** — candidates switched on in `SELECTION:` |
| `sync_final_model.R` writes the decisions into `config.yaml` (value-only edits, comments kept, unapplicable decisions reported) | `FINAL_MODEL` read but filled by hand | **G** |
| Stage report helpers (`stage_table()`, `stage_summary()`, `plot_stage_index()`, `describe_spec()`, `fmt_pair()`, `index_mard()`) | not ported | **G**; candidates for **U** sdmTMBexperiments later |
| Resume semantics: driver skips candidates whose log says `CANDIDATE DONE`; old logs must be moved before a rerun | not documented | **K** (pipeline knowledge) |

### 2.5 Step 4 — report, sensitivity, hand-off

| Piece | Template | Action |
|---|---|---|
| Report computations as separate processes with caches (`report_lib.R`, `report_compute.R`, `run_report.sh`) | ported 0.2.4x | done, but update to the project's version |
| `report_check_stamp()` — report steps stop when `FINAL_MODEL` changed since the cache | missing | **G** |
| Bias-corrected final indices as their own step (`run_report_index_bc()`) | partly | **G** |
| Sensitivity refits with **level ratio and trend change** (`run_report_sensitivity()`, `sensitivity_change()`, `leave_out_trend_change()`) | missing; template has `robustness-section` and `bridging-section` instead | **G** — generic variants: sample-quality subset, major series only, effort as offset with a Poisson-link family, fishable threshold; survey and quality codes from config |
| Residual and zero-share diagnostics by series | missing | **G** |
| Assessment regions for the regional split (`read_assessment_regions()`, `REGIONS_FILE`) | `regions.md` + region section | **G** the reader; region polygons **P** |
| Two hand-offs (`SPICT_CANDIDATE_INDICES`) and a per-stock `SPICT_RECOMMENDED_INDEX` while `SELECTED_INDEX` stays with the assessment project | one `SELECTED_INDEX` | **G** + **K** (`assessment-index-handoff.md`) |
| `bridging-section`, `robustness-section` (template only) | — | keep in the template as optional sections; the project did not need them |

### 2.6 Pipeline, rendering and servers

| Piece | Template | Action |
|---|---|---|
| `R/run_models.sh <sp>`: fit doc → selection + validate doc → config sync → report computations → report → summary, one log line per step, done-flags, stop on the first failure | none | **G** |
| `render.sh` with exit status in the log, `LD_LIBRARY_PATH` restored inside screen | ported | done |
| `docs/render.R <stage> [species]` stage- and species-aware | stage-aware | **G** species argument |
| Cache inventory to move before a full rerun (report, selection, folds, barrier land, fit outputs, `logs/validate/<sp>/`); which caches guard themselves | none | **K** — the main rerun hazard |
| `sdmTMBexperiments` minimum version check in `0_setup.R`; same package versions on laptop/server/HPC | partly | **G** + **K** |
| Sigma2: `R/hpc/slurm/{driver,candidate,assemble,resources,env,site}.sh`, `rename_caches.R`, compute ledger, cost report | none | **G, optional** — only the selection-specific `candidate.sh`/`assemble.sh`/`resources.sh`; driver from hpc-wise `scripts/templates/sbatch-driver.sh` |
| Cache file names from `rlang::hash()` differ between R versions | in hpc-wise `sigma2-olivia.md` | **U** version-independent hash in sdmTMBexperiments; **K** short pointer in `rendering.md` |

### 2.7 Lessons for knowledge and skills only (no code)

- **Trend, not level** (`index-trend-not-level.md`): the level of a survey index depends on
  arbitrary references (month, gear, width) and on shared parameters one survey can move for
  all years; judge sensitivities on a trend change reported beside a level ratio. Put
  `REFERENCE_MONTH` where the main survey samples the bulk of the stock, not at the most
  sampled month (the template default), and take the index timing from it. A month factor
  confounded with survey series acts as a catchability term. → new section in
  `model-selection.md` or a new `knowledge/index-level-and-trend.md`; change the template
  default comment and the interview question.
- **CV design** (`validation-cv-design.md`): space–time blocks sized by the Matérn range; do
  not compare CV results across fold sets; all base-model fold fits must be PD; Tweedie often
  fails to fit or gives no PD Hessian (check, do not assume it was compared).
- **First-fit structures** (`first-fit-diagnostics.md`): symptoms → structural fixes table.
- **SPiCT constraint and recommendation**: a data-poor fishable index cannot carry a year
  factor; without it, the index can exceed the total index — recommend the total index and
  show the fishable one beside it.
- **Influence workflow additions**: flag, do not remove; a leave-one-survey-out influence that
  is the same ratio in every year (including years before the survey existed) is a
  shared-parameter level shift, not a data problem.
- **Render discipline**: review before render; never let a render refit what a stage runner
  should compute; restore toggles; a document reads caches only.
- **Project-memory hygiene**: a `workflow.md` with the order of actions for a full rerun, a
  short `current-status.md`, `MEMORY.md` index — already in the template skeleton; add the
  rerun-order section.
- **hpc-wise**: findings 1–15 of the Sigma2 journal are already in hpc-wise. Not yet seen
  there: `s2 bash -c` quoting (finding 16), `rsync -r` for directory pulls (14), copy logs of
  failed tasks back before deleting a staging folder, smoke-test optional candidates (barrier
  mesh) on the cluster. These are hpc-wise follow-ups; this plan does not change hpc-wise.

### 2.8 Stays project-specific

Species values and thresholds; the ICES 1–2 region and the redfish assessment regions; the
EcoS and G.O.Sars 1998016 investigations; the Russian-exclusion *decision* (the switch is
generic); `SURVEY_NAMES` entries; the data-review response; the Sigma2 journal, ledger and cost
report; the Pages repository; WKBMSYSPiCT5 dates; `lotidae-index` as earlier work.

## 3. Problems found in index-wise while comparing

1. `knowledge/workflow.md` Step 3 and the `index-validate-model` skill *description* still give
   the old order (component ranking → fixed → family → spatiotemporal → mesh); the skill body
   and `model-selection.md` give the new order (mesh first). Fix in phase A.
2. `memory/architecture.md` and `memory/conventions.md` refer to `R/00_setup.R` and
   "index-template"; the file is `R/0_setup.R`. Cosmetic.
3. `REFERENCE_MONTH: null` defaults to the most sampled month, which this project showed can
   tie the index level to one survey. Change the default guidance (keep `null` working).
4. No survey names are hard-coded in the template's report code (`run_report_surveys()` reads
   `cfg$REPORT_SURVEYS`); the project reintroduced them. Keep the template's pattern when
   porting and extend it to the sensitivity variants.

## 4. Template structure

```
<project>/
├── AGENTS.md, CLAUDE.md, VERSION, .here, _quarto.yml, render.sh, publish-site.sh (optional)
├── config.yaml                    # shared keys + SPECIES_SETTINGS: {<sp>: {...}} (N ≥ 1)
│                                  # + PRODUCTS, SELECTION, SENSITIVITIES, REPORT_SURVEYS, SITE
├── R/
│   ├── 0_setup.R                  # merges SPECIES_SETTINGS[[index_species]]; version guard
│   ├── compile_functions.R, index_helpers.R, plot_helpers.R, report_helpers.R,
│   │   fishable_length.R, assessment_index_handoff.R, cpue_helpers.R
│   ├── run_models.sh              # unattended per-stock pipeline
│   ├── validation/                # stage_lib.R, run_candidate.R, assemble_stage.R,
│   │                              # run_species.sh, smoke_test.R, sync_final_model.R
│   ├── report/                    # report_lib.R, report_compute.R, report_plots.R, run_report.sh
│   └── hpc/slurm/                 # optional: candidate.sh, assemble.sh, resources.sh
├── docs/
│   ├── render.R                   # Rscript docs/render.R <stage> [species...]
│   └── benchmark/                 # DOCS_DIR (docs/ for stand-alone indices)
│       ├── assets/                # references.bib, CSL
│       ├── background/0-stock-background.qmd     # all stocks
│       ├── data/<sp>-{1-summary,2-survey-selection,3-data}.qmd
│       └── sdmtmb/
│           ├── fit/<sp>-4-fit.qmd
│           ├── validation/<sp>-5-validate.qmd
│           ├── <sp>/<sp>-6-report.qmd
│           ├── sections/*-section.qmd            # shared, optional by params
│           └── cpue/cpue.qmd                     # optional
├── ai/
│   ├── memory/                    # MEMORY.md, scaffold-interview, workflow (rerun order),
│   │                              # constraints, current-status, data-confidentiality
│   ├── tests/                     # parity, ai-statement, fishable-biomass, config-schema
│   ├── hpc-wise.yml               # written by hpc-wise when a server is set up
│   └── review/                    # ignored
└── data/{source,output/<sp>}/, logs/, figures/   # ignored
```

Scaffolding: `scaffold_index()` writes the master documents for the first stock and calls the
parity generator for the rest; `{{SPECIES_*}}` tokens disappear from analytical documents
(identity comes from `SPECIES_SETTINGS` at run time), so adding a stock later is a config
edit plus `test-species-parity.R write`.

Single vs multi-stock: no separate template. N = 1 projects get the same files with one
prefix; the parity test passes trivially.

## 5. Ordered implementation list

Effort is agent working time with the maintainer reviewing; "session" ≈ half a day.
Every commit in index-wise bumps patch by 0.0.1 through the hook; a minor bump (0.3.0) at the
end of phase B is the natural point but needs the maintainer's explicit request.

### Phase A — knowledge and skills (no code)

| # | Item | Effort | Risk |
|---|---|---|---|
| A1 | Fix stale stage order in `workflow.md` and the validate skill description; `00_setup` names | 0.5 h | none |
| A2 | Trend vs level and reference month (new section/file; template default comment; interview question) | 1–2 h | wording must stay general, not tusk-specific |
| A3 | `model-selection.md`: block-level SE, CV block rule and re-fold trigger, fields shortlist, family order, Tweedie caveat, cruise-series/trawl-model candidates, `sync_final_model` step | 2 h | file is already 650 lines; consider splitting staged-runner mechanics into `knowledge/selection-runner.md` |
| A4 | New `knowledge/pipeline.md`: order of actions for a full rerun, cache inventory and guards, machine split, version pinning, resume semantics, done-flags; pointer from `rendering.md` | 2 h | must match the code of phase B; write it against the project's working scripts |
| A5 | `first-fit` symptoms → fixes table into `sdmtmb.md`; fishable-index/SPiCT recommendation into `assessment-index-handoff.md`; level-shift signature into `influence-diagnostics.md` | 1.5 h | low |
| A6 | `index-new-project` interview: stocks list, benchmark name/dates, reference survey/month, confidential subsets, `FIRST_YEAR` by coverage, machines (laptop/server/HPC), website | 1 h | interview grows; group questions |
| A7 | `memory/third-project-lessons.md` (this project), `reference-sources.md` entry | 0.5 h | none |

Phase A total ≈ 1.5 sessions. Can ship before phase B.

### Phase B — template code

| # | Item | Effort | Risk |
|---|---|---|---|
| B1 | Config schema: `SPECIES_SETTINGS` always, legacy flat config read as one stock; `PRODUCTS`, `SELECTION`, `SENSITIVITIES`, `REPORT_SURVEYS`, `SITE` blocks with defaults; `0_setup.R` merge and version guard; `test-config-schema.R` | 1 session | breaks existing single-stock projects if the fallback is wrong → test both shapes |
| B2 | Document renaming/numbering, shared `sections/`, generalised parity generator; `scaffold.R` writes master + twins; `docs/render.R` species argument | 1 session | scaffold tests and the `{{...}}` stamping change; existing projects keep their names (no migration forced) |
| B3 | Port the stage runner (`R/validation/*`) and rewrite `<sp>-5-validate.qmd` as a cache reader; candidate lists from `SELECTION`; `sync_final_model.R` | 2 sessions | biggest change; the project code has ling/tusk-tuned defaults (`cv_top_n`, fixed candidates). Port from the project's tested code rather than rewriting |
| B4 | Report: port `report_check_stamp`, sensitivity + trend measures, series diagnostics, bias-corrected step, configurable products/surveys/variants; update shared sections and report template | 1.5 sessions | hard-coded `CoastalS`/`EcoS` names must all go; grep check in a test |
| B5 | Summary document reading report caches; Limitations section; hand-off metadata check | 0.5 session | low |
| B6 | `R/run_models.sh` + `run_species.sh` + `run_report.sh` driven by config products; logs layout | 0.5 session | shell portability (BSD vs GNU `sed -i` in `run_species.sh`) |
| B7 | Optional `R/hpc/slurm/` selection jobs + pointer to hpc-wise driver; generated only when the interview says HPC | 0.5 session | duplicates hpc-wise if not kept thin |
| B8 | Optional `publish-site.sh` from `SITE` | 0.5 h | low |
| B9 | Tests: decision rules on synthetic CV tables; sync round-trip on a temp config; parity for N = 1, 2, 3; no-hard-coded-survey grep; `SMOKE=1` stage run on simulated data (sdmTMB `pcod`-style) in `validate-scaffold.R`; CI job for the light tests | 1 session | the smoke run needs sdmTMB in CI (slow); keep it opt-in (`--smoke`) |
| B10 | Port check: scaffold a two-stock test project from synthetic data end to end (fit → selection on a tiny ladder → report) on a server | 1 session | needs server time; synthetic data only (public repo) |

Phase B total ≈ 8–9 sessions.

### Phase C — upstream and follow-ups (outside index-wise, each needs its own go-ahead)

- sdmTMBexperiments: version-independent cache-name hash; consider moving the generic stage
  decision helpers there once stable.
- hpc-wise: the four journal findings not yet there (§2.7).
- ahl-index and other existing projects: optional migration notes; no forced change.

## 6. Risks and open questions for the maintainer

- **Scope of the runner in the template.** Porting the stage runner commits index-wise to
  maintain shell drivers. Alternative: put the runner in sdmTMBexperiments as R functions and
  keep only thin scripts in the template. Recommendation: port to the template now (it works),
  move generic parts upstream later.
- **Bridging/robustness sections.** Keep them as optional sections beside the new sensitivity
  section, or merge robustness into sensitivity? Recommendation: merge into one
  "Sensitivity and robustness" section with variants from config.
- **Twins vs parameters.** Generated twins are proven here; Quarto params would avoid duplicate
  files but were not tested with per-document caches and freeze folders.
- **Version.** Phase B changes file names and the config shape: a candidate for 0.3.0, only on
  the maintainer's request.
- **The project is still changing** (full rerun running 2026-11-25; deferred
  survey-specific dispersion; Tweedie check). Port from the commit after the rerun, and re-diff
  `R/validation/` and `R/report/` before phase B.
