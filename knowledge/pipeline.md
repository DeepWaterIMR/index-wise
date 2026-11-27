# The index pipeline: order, machines, caches and reruns

A benchmark index is rebuilt several times: after a data fix, a reviewer's request, a new
filter. Each rebuild touches every step, takes a day or more of compute, and silently reuses
whatever caches it finds. This file is the order of actions and the cache discipline that make
a full rerun reliable. Rendering details are in `rendering.md`; servers and clusters in
hpc-wise (`server-run`, `sigma2-run`).

## Machines

| Work | Where | Why |
|---|---|---|
| Data compilation (survey selection, data report, stock background) | the machine with the newest Biotic database and access to confidential sources | databases and confidential extracts stay there |
| First fits, model selection, report computations, slow renders | a terminal server (or a cluster for the selection) | hours of single-core fits; must survive a closed laptop |
| Summary, publishing | either | reads caches only |

Code moves by git (read-only deploy key on the server; hpc-wise `sync.md`); `data/output/` and
`data/source/` move by rsync, because `data/` is never committed. **Pin package versions across
machines** (sdmTMB, sdmTMBexperiments, TMB, fmesher): fits and caches from different versions
are not interchangeable, and some cache names depend on the R version (below). Let
`R/0_setup.R` stop on a too-old sdmTMBexperiments rather than produce a silently different
result.

## Order of actions for a full rerun

1. **Investigate before deleting.** Open questions that need the current fits (an influential
   survey, a spike) are answered first, from the caches that are about to go.
2. **Decide the scientific changes** that alter the data or the selection, and record them in
   `ai/memory/` before anything runs.
3. **Fix code and text**, run `ai/tests/*.R`, review the changed chunks, commit and push. The
   server pulls; never edit code on the server.
4. **Move the old caches away** (do not delete them until the new run is checked; see the
   inventory below).
5. **Data documents** on the data machine: survey selection (recompiles), data report, stock
   background. Then rsync `data/output/` and `data/source/` to the server.
6. **First fit** on the server: it writes the base fit (which sets the CV block size) and the
   prediction grid.
7. **Model selection**: mesh stage first, then fields, geometry, fixed effects, family, grid;
   render the validate document from the stage caches.
8. **Write the selected specification into `config.yaml`** (`FINAL_MODEL`, mesh, grid, smoothed
   structure) with `Rscript R/validation/sync_final_model.R <stock>`, never by retyping a table.
9. **Report computations** (product fits, bias-corrected indices, retrospectives, survey
   comparison, leave-one-out, sensitivity refits), then the report document.
10. **Summary** last: it reads the report caches.
11. **Check the hand-off** (`assessment-index-handoff.md`): metadata, timing, years, against the
    report tables.
12. Publish, update `ai/memory/workflow.md` and `current-status.md`.

With several stocks, steps 6–10 run per stock and can run side by side on a server with enough
cores; keep the total within the server's fair share.

## Unattended driver

Steps 6–10 should run without anyone logged in: `R/run_models.sh <stock>` (template). It runs them in order,
writes one log line per step, marks each finished step with a done-flag file, and stops at the
first failure; rerunning it resumes after the last done-flag. Each step checks its own result
(an exit status in the render log, a `DONE` line in a computation log) rather than trusting the
process exit code alone. `R/report/run_report.sh` ends with `FAILED <stock>, missing: ...` (exit 1)
instead of `ALL DONE` when a step left no cache, and removes the logs of uncached steps before a
run, so that an old "Execution halted" does not end the new run's wait loops. Start it in a detached `screen` session that passes `LD_LIBRARY_PATH`
(`rendering.md`).

## Cache inventory and guards

Most expensive results are cached so that renders only read them. A cache that is not invalidated
when its inputs change is the most common source of a wrong result that looks right.

| Cache | Made by | Invalidated automatically? |
|---|---|---|
| Compiled station and length data | survey selection | yes, when the compile toggle is on |
| Base fit, mesh, prediction grid, first indices | first fit | no — move away when the data change |
| CV folds (`cv-folds.rds`) | selection | yes: refused when the hauls change (haul ids are stored with the folds); the block size is not rechecked |
| Barrier land polygon | selection (on a machine with internet) | no |
| Candidate fits and CV results, stage decisions | selection | no — keyed by candidate name, not by the data |
| Driver logs that say a candidate is done | selection driver | no — a resumed driver skips those candidates |
| Report fits, posterior summaries, bias-corrected indices, sensitivity refits | report computations | yes: `report_check_stamp()` stops on a changed `FINAL_MODEL`, grid, references or model data |

Rules:

- **Stamp every cache with what it depends on** (specification, data version) and stop, not
  refit, when the stamp differs. A refit that should have happened on the server can otherwise
  start inside a document render and run for hours.
- **Move the uncovered caches away by hand** before a rerun: base fit outputs, selection folder
  (with folds and barrier land), stage logs, report folder. Keep them until the new results are
  checked.
- **Cache names that contain a hash of an R object differ between R and rlang versions.** Caches
  copied from a cluster with another R version are then invisible and get recomputed.
  sdmTMBexperiments >= 0.1.13 names selection caches with an R-version-independent hash and
  renames caches under the old names on first use; caches copied from another R version that
  were written by 0.1.12 or older need `R/hpc/rename_caches.R` once (hpc-wise `sigma2-olivia.md`).
- **Do not compare cross-validation results across fold sets** (`model-selection.md`).

## Reruns of one piece

- A changed filter or a removed nation changes the data: rerun from step 5.
- A changed decision rule only: rerun the assemble step of the affected stages and every later
  stage; the candidate fits stay valid.
- A changed report section only: rerun its computation (move its cache) and the report render.
- A changed text only: render; no computation.

Related: `rendering.md`, `model-selection.md` (*Caching and resumability*), `workflow.md`.
