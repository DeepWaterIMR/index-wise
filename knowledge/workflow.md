# The index-building workflow

Building a survey index is a **four-step** process. Each step is a skill and produces one or
more Quarto documents in the generated project. Do the steps in order; don't jump to modelling
before the data are clean, and don't add complexity before a simple model works.

index-wise's own steps and documents have their own names (below) — they are **not**
called by the source paper's internal names. This table exists only so an agent that needs to
consult the original background material knows what to look for in those (separate,
IMR-internal) repos:

| index-wise document | Background material, if you need to consult it (Vihtakari et al. 2026) |
|---|---|
| `docs/data-report/survey-selection/compile-data.qmd` | `ref-index-paper/docs/data/{Redfish bottom trawl, BioticExplorer_database, Compile_all_data}.Rmd` |
| `docs/data-report/data-overview/<species>-<region>-data-report.qmd` | `ref-index-paper/docs/SI files/SI-Text-1-data.qmd` |
| `docs/data-report/fit/fit.qmd` | `ref-index-paper/docs/SI files/SI-Text-2-sdmTMB.qmd` |
| `docs/data-report/validation/validate.qmd` | `ref-index-paper/docs/SI files/SI-Text-3-model-selection.qmd` (staged selection, status-coded tables, index per candidate) |
| `docs/data-report/<species>/report.qmd` (+ `*-section.qmd`) | `ref-assessment-index/docs/benchmark/beaked/*` |

As the routine is improved, index-wise's documents will diverge from this original
material — that's expected. Use the table to find *background*, not to decide what the
current documents should contain; **project-template/docs/ is the current, evolving source of
truth for what each step actually does.**

## Step 0 — Scaffold (skill: `index-new-project`)

Run the **questionnaire**, confirm a plan (plan mode), then copy `project-template/` and stamp
`config.yaml` with `scaffold.R`. Seed the project `ai/memory/` with the answers. Output: an empty
but structured project ready for step 1. See `project-structure.md`.

## Step 1 — Compile & report the data (skill: `index-compile-data`)

**Needs a locally installed BES database and an IMR intranet connection.** Use BAIT for access
(`biotic-server-setup`, `biotic-connect`, `biotic-query`).

1. Adapt the `docs/data-report/survey-selection/` compilation document for the species (`filter_sp`). They read
   station and individual data from the Biotic database (via BES) and — for northern/offshore
   species — optionally from legacy **SPD** files.
2. Apply the **critical filtering** (`data-filtering.md`): the `gearcondition`,
   `samplequality`, and `stationtype` tags that make catches quantitative, plus duplicate
   removal and swept-area density.
3. Compile everything into one dataset with true absences (zero catches at fished stations).
4. Generate the **data overview** (`<species>-<region>-data-report.qmd`): station maps, counts by
   year/depth, response distributions, trawl parameters, length–weight and length-group
   allocation.

**Duplicates warning:** the Biotic database can contain duplicate records, and data are still
being added to Biotic (making SPD files gradually obsolete). Detect duplicates and write a
report to `ai/review/`. For **southern or coastal** species, SPD files add little — suggest using
BES only.

## Step 2 — Fit the first feasible model (skill: `index-fit-model`)

The first feasible model. **Start without length groups** — a single total-biomass (or
abundance) model — to confirm the method works before adding complexity.

- `delta_lognormal()` family, `spatial = "on"`, `spatiotemporal = "ar1"`, `time = "year"`.
- Default formula `value ~ 0 + geartype + s(month) + s(depth)` (**no temperature by default**).
- Build the mesh, the prediction grid (GEBCO depth), predict, and compute the index with
  `get_index`. See `sdmtmb.md` and `sdmtmbexperiments.md`.

## Step 3 — Validate / select the model (skill: `index-validate-model`)

Five selection stages, in order: **component ranking** → **fixed effects** → **family** →
**spatiotemporal structure** → **mesh resolution**, then a retrospective. Each is the same
operation with a different thing varied, so all five run through
`sdmTMBexperiments::sdmTMB_selection()`; `sdmTMB_mesh_cv`, `compare_meshes`, `sdmTMB_retro` and
`mohns_rho` cover the sensitivity checks.

**Read `model-selection.md` first.** The method is the comparability contract, not the function
calls: candidates fitted to identical records, only `comparable` rows compared, hold-out
likelihood per observation rather than summed, AIC first and cross-validation on a shortlist,
the winner looked up in the metric column, and an honest statement of the gap whenever the
carried-forward model is not the table's winner.

## Step 4 — Final report + extensions (skill: `index-final-report`)

Modelled on `ref-assessment-index/benchmark/beaked`. Extend the validated model to the full
set of assessment products:

- **Multiple indices**: total biomass, over-X-cm biomass, and length-group abundance indices.
- **Optional include sections** (`*-section.qmd`, switched by a YAML param + a compute
  toggle): mesh comparison, barrier mesh, retrospective, cross-validation, survey comparison.
- **Choose the assessment index** and export it as the `assessment-index.rds` hand-off
  (`assessment-index-handoff.md`) to `data/output`.

Note the structural choice: total/length indices use `spatiotemporal = "ar1"` and **no** year
fixed effect; the assessment-selected index (feeding e.g. SPiCT) often uses `iid` and **year
as a fixed effect** to avoid temporal smoothing. Confirm with the user which the assessment
consumes.

## Throughout

- **Review before rendering.** Renders are slow — code-review changed chunks and fix issues
  first. See `rendering.md`.
- **Render in a screen session** with a log in `logs/`; tell the user the session name;
  suggest a server. Once `data/output` files exist, flip caching toggles to `FALSE`.
- **Write project memory** as you make non-obvious decisions.
