# Review checklist for index-wise projects

The defects that recur in index-wise projects, grouped by where they hide. Each item says what
to look for, why it matters, and where the rule lives. Most items come from revisions of real
projects (halibut, beaked redfish, ling/tusk); the ling/tusk benchmark alone had a dozen of
them fixed after the documents had been rendered and read. The `index-review` skill walks
this list; `skills/index-review/scripts/lint_project.R` finds the mechanical ones (marked
**[lint]**).

A finding is a defect only when the project has not recorded the choice as a decision. Read
the project's `ai/memory/` and `config.yaml` comments first: a deliberate departure is not a
bug, but the documents must then say what was decided and why.

## A. Configuration and code

1. **`$` partial matching on config lists [lint].** `cfg$REFERENCE_GEAR` silently returns
   `REFERENCE_GEAR_MODEL` when the shorter key is absent. Optional keys are read with
   `cfg[["KEY", exact = TRUE]]`.
2. **A setting that the code ignores.** A config switch (`FISHABLE_YEAR_EFFECT`, a family,
   a reference month) honoured in one document but not in the report or the hand-off. Trace
   each analytical key to every place that should use it. Dead keys **[lint]** are removed
   or wired in `R/0_setup.R`.
3. **Two implementations of one rule.** Mesh choice, prediction-grid building, family rule,
   or cruise-series grouping written once in a document and again in a helper or runner, so
   they drift. There is one function per rule and every stage calls it.
4. **The selected model is not the model that is fitted.** `FINAL_MODEL` (written by
   `sync_final_model.R`) must match the winner of the selection tables; the report and the
   hand-off fit that specification. See `model-selection.md`.
5. **Hard-coded values that exist in config.** `50 %`, a mesh in km, a reference month, or a
   year range typed into code instead of read from `cfg`.
6. **Dead code [lint].** Unused functions, one-off scripts, helpers copied from another
   project. Duplicate function definitions **[lint]**: the last sourced one wins.
7. **Floating-point binning.** Lengths converted from metres to cm and binned without
   rounding shift fish into the neighbouring bin.

## B. Data compilation

Rules live in `data-filtering.md`; check that the code still follows them.

1. Station key `missionid + serialnumber` (BES); cruise keys platform + cruise (cruise
   numbers are reused); never keys from vessel or cruise labels.
2. `stationtype` keep-list, the NA-safe sample-quality predicate, documented
   `gearcondition` codes; a code-2 exception carries its reason.
3. A catchsample row is not a haul: catch parts resolved before summing; densities never
   averaged across unequal effort (sum numerators and denominators).
4. SPD ↔ Biotic duplicates matched by position and time; same-position hauls by vessel.
5. The current, incomplete year is excluded unless the survey has finished.
6. True zeros: hauls of surveys that recorded the species, nothing more and nothing less.
7. The region polygon: a buffer must not carry the region into neighbouring areas whose hauls
   were filtered out; map caps must not drop hauls; the polygon release matches the one that
   assigned the area codes.
8. Cruise series with too few years grouped into `Other` by a configured threshold, not by
   hand.
9. Metadata read before a rename or filter that changes the identifiers it is joined on.

## C. Model and selection

1. **Comparability** (`model-selection.md`): identical records, only `comparable` rows
   compared, ELPD per observation, the winner looked up in the metric column, never at row 1.
2. **Stale cross-validation.** Folds re-made when the hauls change; block-level paired SE
   from fold-group sums.
3. **A component with no time signal.** A model without a year factor and without a
   spatiotemporal field (in the component that carries the index) gives a flat index. The
   fishable or smoothed model must keep a year effect or a temporal field.
4. **Empty factor levels in refits.** Retrospective peels and leave-outs drop month, gear or
   series levels without positive catches, or every refit fails.
5. **Sanity checks.** Non-converged fits, `sigma_E → 0`, large gradients, or a fishable
   index above the total index are reported, not silently carried forward.
6. **Units.** kg vs kt vs tonnes across the compiled index, `get_index_split()` output and the
   survey comparison; the axis label matches the scale.
7. **Bias correction.** Only the final indices are bias-corrected, and every output labelled
   bias-corrected actually is.

## D. Interpretation

Rules: `index-level-and-trend.md`, `influence-diagnostics.md`.

1. **Trend, not level.** Leave-outs and sensitivities report a level ratio *and* a trend
   change; conclusions rest on the trend. A uniform ratio across years is a level shift.
2. **Neutral wording.** A trend change is stated, not judged; no "robust", "confirms" or
   "clearly" without the number that supports it.
3. **Overclaims.** Catchability, availability, and survey differences are not abundance
   change; a single survey's influence is not proof of a population signal.
4. **The recommended index** for the assessment matches `SPICT_RECOMMENDED_INDEX` (or the
   equivalent) and the hand-off file (`assessment-index-handoff.md`).

## E. Text versus code and outputs

1. **Numbers in prose [lint, INFO].** Every count, percentage, threshold or setting in the
   text comes from inline R or is a fixed fact. Typed numbers go stale at the next rerun.
2. **Statements that are true for one configuration.** A reference-month paragraph, an SPD
   data-flow box, a nation exclusion sentence, or a gear statement shown when the setting is
   off. Make it conditional on the config.
3. **Stale descriptions.** Text describing an earlier mesh, family, month term, response,
   or grid; a caption that names a removed term.
4. **Species parity.** In multi-stock projects the stock documents differ only where the
   stock differs. Run the project's `ai/tests/test-*-parity.R`; read any other difference.
5. **Labels that lie.** A file, table or legend called "bias-corrected", "fishable" or
   "final" whose content is something else.
6. **Rendered output [lint].** `?@fig-` (unresolved cross-reference), `NA`, `NaN`, `NULL`,
   `character(0)` or `Error in` in prose; an HTML older than its source or `config.yaml`.

## F. Quarto mechanics [lint]

1. A backtick inside an inline R string ends the code early.
2. A caption that starts with `[` is read by YAML as a list; the cross-reference fails
   without an error.
3. Duplicate chunk labels; `@fig-`/`@tbl-`/`@lst-` references without a label.
4. Citations missing from the bibliography; preprints cited where the paper is published;
   one bibliography per project.
5. `$\rho$` and other maths in pdflatex output; grep the render log for `Unable to resolve
   crossref` (`rendering.md`).
6. Missing AI statement: run `ai/tests/test-ai-statement.R`.

## G. Pipeline and caches

Rules: `pipeline.md`, `rendering.md`.

1. Caches guarded by a specification stamp; a cache that loads after the config changed is a
   silent bug. Cache names carrying an R-version hash are renamed, not refitted.
2. Compute toggles left `TRUE` after outputs exist (expensive re-renders), or `FALSE` before
   outputs exist (the document loads nothing).
3. Output folders created on a clean rerun; render order (summary last).
4. Server wrappers export `LD_LIBRARY_PATH`; forked workers; logs in `logs/`.

## H. Privacy and repository hygiene

1. No raw records, positions or Biotic-derived tables tracked by git **[lint]**; `data/`,
   `logs/` and `ai/review/` stay ignored.
2. No personal absolute paths in code or documents **[lint]**; memory notes may name a
   machine path only when nothing else would do.
3. Confidential subsets (nations, reference fleets) are described only in aggregate.
4. Unfilled `{{...}}` placeholders and `TODO`/`(rerun)` markers **[lint]**.
