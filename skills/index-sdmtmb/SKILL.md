---
name: index-sdmtmb
description: Explain, write, review, or debug an sdmTMB survey index in any project or folder layout — response and offsets, coordinates in km, mesh, delta and Tweedie families, spatial and spatiotemporal fields, extra_time, prediction grids, get_index and bias correction, sanity() and residuals, comparable model selection (AIC, cross-validation), and the assessment constraint on the spatiotemporal structure. Use for any sdmTMB index question ("why does my index fail sanity()?", "which family?", "is this AIC comparison valid?") in an existing repository, or before writing or reviewing index model code; use the index-* step skills inside a scaffolded index-wise project.
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


# sdmTMB survey indices in any project

The method-level index-wise skill: what an agent needs to read, write, review, or explain an
sdmTMB survey index wherever the code lives. It does not scaffold anything and does not assume
index-wise's folder layout.

**Detect the project first.** A `config.yaml` with `SPECIES_SLUG` and `FILTER_SP` and a
`docs/data-report/` folder means a scaffolded index-wise project: follow the step skills
(`index-compile-data` → `index-fit-model` → `index-validate-model` → `index-final-report`).
Otherwise, work in the user's own structure and conventions, and use this skill.

**Authority order:** the installed source (`args(sdmTMB::sdmTMB)`, `?sdmTMB::get_index`,
`packageVersion("sdmTMB")`) > sdmTMB GitHub and NEWS > the sdmTMB site
(<https://pbs-assess.github.io/sdmTMB/>) > the pack knowledge below. State the version you checked.

## Read, in this order, as the task needs

| Need | Pack file |
|---|---|
| Model building blocks, code, gotchas | `knowledge/sdmtmb.md` |
| Comparing candidates, mesh choice, families, CV | `knowledge/model-selection.md` |
| Helpers for grids, maps, selection, retro, CV | `knowledge/sdmtmbexperiments.md` |
| Sampling units, true zeros, swept-area density, own-data contract | `knowledge/data-filtering.md` |
| Study-region polygons | `knowledge/regions.md` or `index-make-regions` |

## Checklist before trusting an index

1. **Response.** Density per swept area, or catch with a log swept-area offset. With a delta
   family the offset enters only the positive part unless `type = "poisson-link"`.
2. **Data.** One row per sampling unit, true zeros kept, numerators and denominators summed
   before dividing. Biotic data go through BAIT and `biotic-survey-analysis`.
3. **Coordinates in km**, from `add_utm_columns()`; keep the CRS for the grid and maps.
4. **Missing survey years** with `ar1`/`rw`: pass `extra_time`.
5. **`sanity()`** read and reported; a failing fit can be the mesh draw, not the model.
6. **Grid** covers the survey domain only, with reference levels for fixed effects, and
   `area` in the response's area unit.
7. **`bias_correct = TRUE`** for a final index, or say why it was not used.
8. **Comparable selection:** identical records, one likelihood scale, per-observation hold-out
   likelihood, winner read from the metric column. Prefer `sdmTMBexperiments::sdmTMB_selection()`.
9. **Assessment use:** an index for SPiCT or gadget is often `spatiotemporal = "iid"` with year
   as a fixed effect, so the assessment model sees an unsmoothed series. Say which was carried.

## Writing and reviewing code

- Use `r-code-style` for any R created or edited, and the project's own style where it differs.
- Use the `sdmTMBexperiments` helpers rather than hand-rolled loops when the project already
  uses or allows them; otherwise reproduce the convention and cite the knowledge file.
- Long fits and renders: run detached with a log (see `knowledge/rendering.md`).
- Exported indices that feed an assessment follow `spict-wise`'s index contract (`year`, `est`,
  `se` on the log scale); record the producing commit.
