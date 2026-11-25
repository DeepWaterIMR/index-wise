---
name: workflow
description: Progress through the index workflow, the document layout, and the order of actions for a full rerun.
metadata:
  type: project
  author: <agent>
  created: <YYYY-MM-DD>
---

# Workflow status

Update as steps complete. See the index-wise `workflow.md` knowledge file for detail.

- [ ] **Step 1 — Compile & report data** (`docs/data/`). `<stock>-2-survey-selection.qmd` selects the surveys
  and compiles the data; `<stock>-3-data.qmd` reports the compiled data;
  `<stock>-0-background.qmd` gives the stock background and the fishable length
  (structure: index-wise `knowledge/data-documents.md`). Survey list, filters applied,
  duplicates found, SPD used?  _<notes>_

Survey qualification is mission-level: build the qualifying `missionid` set from positive target
catches first, then retain all valid hauls from those missions. Never backfill an entire cruise
series merely because one of its surveys qualifies.
- [ ] **Step 2 — First model** (`docs/sdmtmb/fit/<stock>-4-fit.qmd`). No length groups. Mesh cutoff,
  sanity result.  _<notes>_
- [ ] **Step 3 — Validate / select** (`docs/sdmtmb/validation/<stock>-5-validate.qmd`). Family,
  spatiotemporal structure, mesh, retro decisions.  _<notes>_
- [ ] **Step 4 — Final report + export** (`R/report/run_report.sh <stock>`, then
  `docs/sdmtmb/<stock>/<stock>-6-report.qmd`). Products, selected index, export path.  _<notes>_
- [ ] **Step 5 — Summary** (`docs/data/<stock>-1-summary.qmd`, rendered last).  _<notes>_

Steps 2–5 run unattended on the server with `R/run_models.sh <stock>`. `<stock>` is each stock
key of `config.yaml` (one line per stock above when there are several).

**Order of actions for a full rerun:** follow index-wise `knowledge/pipeline.md`; record here
any project-specific step (machines, sync commands, caches to move away).

**Cached outputs in `data/output/`:** _<list files so re-renders can load them>_.
