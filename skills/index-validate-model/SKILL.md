---
name: index-validate-model
description: Step 3 of the index workflow — validate and select the sdmTMB model via cross-validation and sensitivity analysis (component ranking, fixed effects, family, spatiotemporal structure, mesh resolution, retrospective). Use after a first feasible model works (step 2).
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


# Step 3 — Validate / select the model

Goal: leave behind a **defended specification** — formula, family, spatiotemporal structure,
mesh cutoff, barrier — with the evidence for each and an honest note wherever the carried
model is not the winner.

**Read `knowledge/model-selection.md` first**, then `knowledge/sdmtmbexperiments.md`. The
method is the comparability contract in the first file; the functions are only the mechanics.
Use `sdmTMBexperiments::sdmTMB_selection()` — do not hand-roll a CV loop.

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Work in `docs/data-report/validation/validate.qmd`

Each stage has its own compute toggle and its own cache prefix. Adapt the candidate lists to
the species and config. The order and its reasons are in `knowledge/model-selection.md`; in
short, start from the Step 2 model and settle the most expensive, most conditioning setting
first:

1. **Mesh resolution** — a cutoff ladder; choose the **coarsest mesh from which the index has
   stabilised**: it and every finer cutoff within 5 % of the finest mesh in the terminal year,
   over the last five years (the mesh Δρ, after Mohn's rho) and over the whole series. Show the
   four-panel selection figure (ΔELPD, Δρ, fit time, index); ELPD is supporting, not decisive.
2. **Random-field structure** — spatial field on/off per component, `ar1`/`rw`/`iid`. Remember
   the assessment use-case: total/length indices → `ar1` with no year effect; the
   assessment-selected index → often `iid` + `year` as a fixed effect, to avoid temporal
   smoothing. Confirm with the user which the assessment consumes.
3. **Barrier and anisotropy** — sensitivity of the index to each, on the selected mesh.
4. **Fixed effects** — the full model, each term dropped in turn, candidate additions. Survey ×
   gear is usually not estimable; flag misrecorded gear in the data report.
5. **Family re-check** — the Step 3a winner against its runners-up with the selected structure.
   Prefer a Poisson-link delta family with a swept-area offset when it fits at least as well
   and converges. Candidates on different response scales need the Jacobian correction.
6. **Grid resolution** — after the fit: the coarsest grid whose index matches the finer ones.

AIC ranks every ladder; cross-validate a shortlist only. Residuals (DHARMa), retrospectives,
interval widths and comparison with an existing index are **diagnostics of the final model**
(Step 4), not selection criteria.

**Every stage produces three outputs**: the table, `plot(sel)` (status-coded ranking), and
`plot(sel, type = "index", newdata = grid)`. The third is the one that decides whether the
stage mattered — a choice that does not move the index is not worth arguing about.

## Non-negotiables

- **Identical records.** Build the selection frame once with `selection_frame()`; fit the
  chosen specification to the full data afterwards.
- **Compare only `comparable` rows**, and never quote a delta unless both candidates are
  comparable. `sanity()` is reported but does not gate comparability.
- **Look the winner up in the column** (`best_candidate()`), never at row 1.
- **State the full specification**, not a row label.
- **Record the gap** when the carried-forward model is not the table's winner.

## Toggles & rendering

CV, mesh comparison and retros are the slowest steps — each is behind its own toggle, and
`sdmTMB_selection(cache_dir =)` caches one file per candidate so an interrupted stage resumes.
`only = "<candidate>"` spreads a long stage across R sessions when memory is the constraint.
**Code-review before rendering**; render via `index-render` in a screen session with a log;
**suggest running on a server**. Flip toggles to `FALSE` after the first successful render.

## Output

A defended model specification and a short "Decision" section stating it, the evidence, and any
deliberate divergence from the table. Record it in project memory.

## Next

Step 4 — final report and extensions (`index-final-report`).
