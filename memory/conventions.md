---
name: conventions
description: House rules for editing the index-template repo.
metadata:
  type: feedback
  author: claude
  created: 2026-07-02
---

# Conventions for editing this repo

- **No data, no private paths — ever.** Public repo. `.gitignore`/`.claudeignore` block data
  extensions as a safety net; the responsibility is still yours. Placeholders + code only.
- **Keep detail in `knowledge/`, keep skills short.** A `SKILL.md` routes and links into
  `knowledge/`; don't duplicate long explanations across skills.
- **Don't reinvent helpers.** Generic sdmTMB helpers belong in `sdmTMBexperiments`; propose
  them there rather than adding logic here.
- **Markdown** wrapped ~92 cols; **`.qmd`/`.Rmd` prose is NOT hard-wrapped** (one paragraph per
  line) — user uses soft-wrap editors.
- **Raster figures** `fig-format: jpeg`; keep generated HTML small.
- **Scaffold stamps identity only.** Analytical settings live in `config.yaml`, read at run
  time. If you add a config field, wire it in `project-template/R/0_setup.R`, not as a
  stamped token.

Related: [[architecture]].
