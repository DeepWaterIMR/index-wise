---
name: third-project-lessons
description: Reusable lessons from the ling/tusk ICES 1-2 benchmark indices (lotidae-assessment-index), Nov 2026; what was ported and what waits for the template plan.
metadata:
  type: decision
  author: Claude Opus 5.5 (supervised by Mikko Vihtakari)
  created: 2026-11-25
---

# Lessons from the ling/tusk benchmark (third project)

Source: `lotidae-assessment-index` (ling `lin.27.1-2`, tusk `usk.27.1-2`, WKBMSYSPiCT5), scaffolded
from index-wise 0.2.x on 2026-11-05. Full gap analysis and plan: `ai/reports/index-wise-template-plan.md`.

Ported to knowledge in phase A (2026-11-25):

- **Trend, not level** → `knowledge/index-level-and-trend.md`: reference month where the main survey
  samples the bulk of the stock; level ratio beside trend change; the uniform-ratio signature of a
  shared-parameter level shift (tusk EcoS through the August month effect).
- **CV** → `model-selection.md`: block-level paired SE (template `paired_se()`, `cv_groups()`),
  re-make folds when the data change, field shortlist, Tweedie often unfit, cruise-series and
  trawl-model candidates, staged runner outside the document.
- **Pipeline** → `knowledge/pipeline.md`: order of a full rerun, laptop/server split, cache inventory
  and stamps, unattended driver with done-flags.
- **First-fit symptoms** → `sdmtmb.md`; fishable-index recommendation and timing →
  `assessment-index-handoff.md`; level ratio in leave-outs → `influence-diagnostics.md`.
- Interview: reference month, `FIRST_YEAR` by coverage, confidential sources, several stocks,
  machines, benchmark dates and website.
- Sigma2 findings were already in hpc-wise (`sigma2-olivia.md`, `estimation.md`).

Not yet in the template (phase B of the plan): the two-species layout (`SPECIES_SETTINGS` merged by
`R/0_setup.R`, `index_species` per document, twin documents written by a parity script, shared
report `sections/`, documents numbered 0–6), the per-candidate stage runner (`R/validation/`), the
config sync of the selected model, `run_models.sh`, report specification stamps and sensitivity
refits with trend measures.
