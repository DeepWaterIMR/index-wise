---
name: workflow
description: Progress through the four-step index workflow for {{SPECIES_NAME}}.
metadata:
  type: project
  author: <agent>
  created: <YYYY-MM-DD>
---

# Workflow status — {{SPECIES_NAME}}

Update as steps complete. See the index-wise `workflow.md` knowledge file for detail.

- [ ] **Step 1 — Compile & report data** (`docs/data-report/`). `compile-data.qmd` is the survey-selection
  document; `<species>-<region>-data-report.qmd` is the compiled-data overview. Survey list, filters applied,
  duplicates found, SPD used?  _<notes>_

Survey qualification is mission-level: build the qualifying `missionid` set from positive target
catches first, then retain all valid hauls from those missions. Never backfill an entire cruise
series merely because one of its surveys qualifies.
- [ ] **Step 2 — First model** (`docs/data-report/fit/fit.qmd`). No length groups. Mesh cutoff,
  sanity result.  _<notes>_
- [ ] **Step 3 — Validate / select** (`docs/data-report/validation/validate.qmd`). Family,
  spatiotemporal structure, mesh, retro decisions.  _<notes>_
- [ ] **Step 4 — Final report + export** (`docs/data-report/{{SPECIES_SLUG}}/report.qmd`). Products,
  selected index, export path.  _<notes>_

**Cached outputs in `data/output/`:** _<list files so re-renders can load them>_.
