---
name: second-project-lessons
description: Reusable lessons ported from the beaked redfish benchmark (ref-assessment-index), Jul–Nov 2026.
metadata:
  type: decision
  author: claude
  created: 2026-11-04
---

# Lessons from the redfish benchmark (second project)

Source: `ref-assessment-index` beaked benchmark (`docs/benchmark/beaked/`) and its `memory/`. Generic functions went into sdmTMBexperiments 0.1.9 and RstoxUtils; this pack documents and calls them.

- **Data compilation** (`knowledge/data-filtering.md`, `compile-data.qmd`): `stationtype` keep-list (missing, 1, 3, 9, 13) replaces the drop-list C/2/A/E, which let multi-codend codes 4–8 through. Cruise numbers are reused by vessels, so cruise keys are platform + cruise. SPD ↔ Biotic duplicates are matched by position and time (`RstoxUtils::match_spd_biotic()`). Documented exclusions live in `config.yaml` `EXCLUDE_CRUISES`. Record swept widths; check the density column even when the model uses an offset.
- **Influence workflow** (`knowledge/influence-diagnostics.md`, `influence-section.qmd`): region split → density screen → leave-one-out with leverage (`influence ≥ 0.1`, `leverage ≥ 2`) → data-filter scenarios. Prefer general rules; a named exclusion only when none works. Haul-level rules and tow-length limits failed; dropping a cruise series distorted other years.
- **Survey comparison**: pass the compiled index in the same units as `get_index_split()` output (a kg/kt slip hid the reference line); add leave-one-survey-out; drop series nested in a combined series.
- **Rendering** (`knowledge/rendering.md`): forked `multicore` workers survive SSH logout; ~75 000 grid rows per bias-corrected split; export `LD_LIBRARY_PATH` through a wrapper on servers; per-chunk JPEG on maps only (70 → 32 MB); bracketed captions break crossrefs silently; `$\rho$` in pdflatex; fallback chunks for optional sections.
- **Not adopted**: the benchmark committed small index `.rds` files under a bulk-ignored output folder. index-wise keeps all of `data/output/` untracked; the versioned hand-off is the shared artefact.
