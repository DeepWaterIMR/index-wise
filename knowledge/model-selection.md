# Model selection for a survey index

Step 3 has to leave behind a **defended specification**: formula, family, spatiotemporal
structure, mesh cutoff, barrier. This file is the method. The mechanics are in
`sdmTMBexperiments::sdmTMB_selection()` and friends — see `sdmtmbexperiments.md` for the
catalogue and `?sdmTMB_selection` for the argument reference. **Use the helpers; do not
hand-roll a CV loop.**

A selection table is easy to produce and easy to get wrong. Almost every way it goes wrong is
a comparability failure — two rows that look like they answer the same question but do not.
The rules below exist to stop that, and each is enforced or reported by the helper.

## The comparability contract

1. **Identical records.** AIC and hold-out log-likelihoods only compare models fitted to the
   same response data. If one candidate carries `s(depth)` and another does not, and `depth`
   has gaps, `sdmTMB()` silently drops different rows for each and the AIC column compares two
   different quantities. Build the complete-case frame **once**, up front:

   ```r
   dt_sel <- selection_frame(dt, candidates, extra = c("X", "Y", "year"))
   ```

   `sdmTMB_selection(complete_cases = TRUE)` (the default) does this for you and reports how
   many rows it dropped. Then fit the **selected** specification to the full `dt` — there is no
   reason to keep discarding records because a covariate that did not enter the model is
   missing for them.

2. **AIC is not comparable across different response data.** Same formula, different response
   (biomass vs abundance), or a positive-only Gamma beside a zero-inclusive Tweedie: these have
   no common likelihood scale. Do not put them in one weighted table. `add_aic_weights(group =)`
   exists for the case where you must show them side by side — weights are then computed within
   each group and left blank for singletons. Delta families and Tweedie *on the same response
   column and the same rows* **are** comparable; that is the family-selection stage.

3. **Hold-out log-likelihood per observation, never summed.** A summed hold-out likelihood
   rewards whichever candidate scored the fewest points. `sdmTMB_cv_summary()` divides by
   `n_heldout` and reports `n_heldout` and `folds_pdhess` beside it, so a fragile row is
   visible as such. This is why the plain `sum_loglik` from `sdmTMB::sdmTMB_cv()` (and the
   default metric of `sdmTMB_mesh_cv()`) needs care when candidates differ in size.

4. **Only compare rows marked `comparable`.** It is `TRUE` for a candidate that fitted, whose
   Hessian was positive definite, that saw the modal number of records, and — under CV — every
   fold of which resolved. **Never quote an AIC or NLL difference unless both candidates are
   comparable.** A likelihood from a fit that did not resolve is not evidence.

5. **`sanity()` is reported, not a gate.** `sdmTMB::sanity()` fails routinely on perfectly
   usable fits (`se_magnitude_ok`, `sigmas_ok`), so it does not gate `comparable` — gating on it
   would drop the best-fitting candidate from every comparison. Read it as a reason to consider
   simplifying, and say so in the text when the selected model fails it.

6. **Look the winner up in the column, never at row 1.** The table's sort key changes with
   whether CV ran. Use `best_candidate(sel)`; in prose, quote the gap with a value read from
   the table, not typed in by hand.

7. **State the full specification, not a label.** Every row of the table carries a `spec`
   column (formula | family | spatial | spatiotemporal). Print it, or at least the `formula`
   column: a reader cannot tell what "Model 3" was.

## The stages

Each stage is the same operation with a different thing varied, so all of them use
`sdmTMB_selection()` with a different `candidates` list. Every comparison is conditional on the
settings held fixed while it runs, so the order matters: start from the first feasible model of
Step 2, settle each setting in turn, and fix its winner before the next stage varies something
else.

| Stage | Vary | Typical candidates |
|---|---|---|
| 1. Mesh resolution | `cutoff` | A ladder from the Step 2 cutoff down to the finest the machine can afford, e.g. 100, 75, 50, 35, 25 km |
| 2. Random-field structure | `spatial` (per component), `spatiotemporal` | Spatial on/off in each delta component × `ar1`/`rw`/`iid` |
| 3. Spatial correlation geometry | barrier mesh, `anisotropy` | Isotropic, anisotropic, barrier (sensitivity, not ranking) |
| 4. Fixed effects | `formula` (drop one term, add one) | Full model, each term dropped in turn, candidate additions such as `s(month)` |
| 5. Family re-check | `family` | The Step 3a winner against its runners-up, now with the selected structure |
| 6. Prediction grid | grid cell size | Not a model choice — see *Grid resolution* below |

**Why the mesh comes first.** The mesh fixes the resolution at which every random field can
express spatial structure, and fit time and memory scale with its vertex count, so every later
stage is both conditioned on it and paid for by it. Settling it first on the Step 2
specification keeps the later ladders affordable. If a later stage changes the random-field
structure substantially (spatial fields reinstated, say), re-check the mesh once at the end.

**Why the random fields come before the formula.** Whether a spatial field is estimable, and
whether an AR1 field has absorbed the persistent spatial pattern (correlation at or near 1), are
properties of the field structure on a given mesh. A fixed effect such as `s(depth)` competes
with the spatial field for the same signal, so ranking fixed effects under a field structure
that will later change ranks them against the wrong alternative.

Earlier versions of this file ranked components and fixed effects first and the mesh last. That
order is still valid when the Step 2 mesh is already close to final. When the Step 2 mesh is a
deliberately coarse smoke-test mesh it is not, because the mesh decision would re-open every
comparison made on it.

Stage 2 has an assessment constraint, not just a statistical one — see the section below.

## Mesh resolution: the coarsest mesh that does not move the index

A finer mesh is not a better model by default. It is a larger one: more random-field vertices
per time step, longer fits (time grows roughly with the square of the vertex count), more
memory, and more chances for a variance parameter to collapse. And the mesh is a computational
setting, not a hypothesis about the stock: what matters is whether it changes **the index the
assessment will read**, above all its terminal years.

Cross-validated predictive skill is the wrong primary criterion for this choice. Held-out
log-likelihood usually keeps improving as the mesh is refined, because a finer field fits
local, station-scale structure. That structure mostly integrates out when the field is summed
over the prediction grid, so a large ELPD gain can come with no change in the index. Selecting
on ELPD therefore pushes the mesh towards the finest one tested, at many times the cost.

Select the cutoff instead by the stability of the index, in the spirit of Mohn's rho (Mohn
1999): treat each coarser mesh as a perturbation of a fine reference mesh and ask how far it
moves the end of the series.

1. **Fit a ladder** of cutoffs from coarse to as fine as is affordable (e.g. 100, 75, 50, 35,
   25 km), with everything else at the Step 2 settings. Predict each fit on the same grid at the
   same reference and compute the index without bias correction.
2. **Take the finest mesh as the reference** and, for every cutoff, compute the relative
   difference of the annual index from it, $r_t = I_{c,t} / I_{\mathrm{ref},t} - 1$, and three
   summaries:
   - the **terminal-year difference** $r_T$;
   - the **mesh $\Delta\rho$**, the mean of $r_t$ over the last $n$ years ($n = 5$, the usual
     retrospective window) — Mohn's rho with mesh coarsening in place of data peeling;
   - the **mean absolute relative difference** over the whole series, which guards against a
     mesh that matches the end of the series but distorts its trend.
3. **Check the ladder:** if the differences shrink steadily towards the reference but the
   second-finest mesh is still outside the tolerance, the reference is not yet a reference;
   extend the ladder before choosing. If they scatter without a trend, the ladder is adequate.
4. **Choose the coarsest cutoff whose three summaries are all within the tolerance** $\tau$.
   Also report whether every finer cutoff is within it (the index has *stabilised*). Do not
   require stabilisation: the differences often scatter non-monotonically around the reference
   by a fraction of the index standard error (Atlantic halibut N62: 50 km within 1 %, 35 km at
   5.8 %), and requiring it would force the most expensive mesh. When the differences scatter,
   say so and read them as noise around the reference rather than a converging sequence.
   The default is $\tau = 0.05$: an order of magnitude below the Mohn's rho values usually
   regarded as acceptable for an assessment (about −0.15 to 0.20 for longer-lived species;
   Hurtado-Ferro et al. 2015) and well inside the coefficient of variation of a typical survey
   index. Use a smaller tolerance if the index CV is small.

Report vertex count, fit time and fitted-object size beside the three summaries, and show the
selection as one four-panel figure (`plot_mesh_selection()` in the template's `validate.qmd`):
(a) ΔELPD ± 2 paired SE, when the ladder was cross-validated; (b) the mesh $\Delta\rho$ and the
terminal-year difference against the cutoff, with the tolerance band; (c) fit time labelled with
the vertex count; (d) the index under every cutoff. The selected mesh is where (b) enters the
band, read against the cost in (c). Report the cross-validated
ELPD as well, as supporting information — a cutoff that is much worse on ELPD *and* moves the
index is clearly too coarse — but do not select on it.

After the other stages are settled, confirm once that the selected cutoff still meets the
tolerance against the reference under the final structure, since a reinstated spatial field or
a different formula can change how sensitive the index is to the mesh.

## Spatial correlation geometry: barrier and anisotropy

Coastlines and fjords make Euclidean correlation wrong near land. A barrier mesh
(`sdmTMBextra::add_barrier_mesh()`) stops correlation crossing land; an anisotropic field
(`anisotropy = TRUE`) lets correlation run further along the coast than across it. Both matter
most where a narrow, coast-parallel distribution meets a ragged coastline, and least where the
area they influence (fjords, sounds) is small compared with the open shelf the index integrates.

Treat both as **sensitivity checks on the selected mesh**, not as ranking candidates: fit the
selected specification with and without each, and compare the indices and the per-cell
predictions with `compare_models()`. Adopt one only if it changes the index or is clearly
preferred on the selection metric. sdmTMB does not combine a barrier mesh with anisotropy, so
the comparison is three models (isotropic, anisotropic, barrier), not a 2 × 2.

## Fixed effects: design terms need care

- **Survey and gear are usually not crossable.** Most survey series fish one standard gear, so
  `cruiseseries * geartype` is not estimable, and even the additive model identifies the gear
  effect only from the series that used both gears. Check the series × gear cross-table in the
  data report before fitting anything. A series with a handful of hauls of the other gear is
  more likely a recording error than a design feature, and must be flagged there.
- **Drop a design term the data do not need.** If removing the series term does not worsen the
  selection metric, drop it: one factor fewer is one reference level fewer to defend.
- **Choose the prediction reference explicitly** (series, gear, month, catchability covariates).
  It sets the index level, not its shape, but it must be a level with good coverage in the data.
- **Check balance over time, not only the series × gear cross-table.** A gear or survey whose
  share of hauls swings between years is confounded with the year effect: its catchability is
  estimated from a few years and the shift can be read as a trend. The data report's
  `design_balance()` tables flag such levels; decide before fitting whether to drop, model or
  accept them.
- **Catchability covariates** (time of day, sun altitude; `CATCHABILITY_TERMS`) are candidates
  in this stage like any other term. Add them where the species is known to migrate vertically,
  keep them only if they earn their place, and predict at the configured reference.
- **Depth limits.** Limit the prediction grid at a depth comfortably beyond the deepest positive
  catch. If the depth smooth falls to negligible density before that limit, the limit does not
  affect the index; check this rather than assume it.
- **Missing years in an AR1 or RW series.** A year with no survey breaks the time steps. Pass
  the gap to `sdmTMB(extra_time = ...)` so the process stays evenly spaced; sdmTMB prints the
  vector it wants.

## Simpler models converge more often

Every index product (total, length groups, the assessment index) must converge with the same
structure. A specification that only just converges for total biomass will often fail for a
sparser length group. When two candidates are not distinguishable on the selection metric,
prefer the simpler one, and confirm that the chosen structure converges for every product before
calling the selection final.

"Not distinguishable" needs a rule, stated before the results are seen. Use the
**one-standard-error rule** (Hastie et al. 2009, §7.10): among the *eligible* candidates
(converged, comparable, passing `sanity()`), choose the one with the fewest parameters whose
cross-validated ELPD is within one **paired** standard error of the best. The paired SE comes
from the per-observation differences on one shared fold assignment, which is far smaller than
the SE of either ELPD alone. Apply the same rule to every stage, the formula stage included —
an exception for "best ELPD" there quietly re-admits the larger model.

## Confirm the final specification one setting at a time

The staged search above carries each winner forward, so later stages are conditional on earlier
choices. Once a specification is in `config.yaml`, confirm it **one setting at a time**: for each
stage, vary that setting alone around the final model and hold every other setting at its final
value. If any stage's selection differs from the final model, report it as an inconsistency,
update `config.yaml`, and re-render until every comparison agrees with the model being carried.
This makes each table a direct check on the reported model rather than on an intermediate one.

## Selection criteria versus diagnostics of the final model

Select on predictive skill (cross-validated ELPD, with AIC as a first filter), convergence and
`sanity()`, and the effect on the index. The following are **diagnostics of the final model**,
not criteria for choosing between candidates:

- **Simulation-based residuals** (DHARMa). Slow to compute and, across candidates of one family,
  usually alike. Compute them for the final model only, behind a toggle, and cache the residual
  object so a re-render does not recompute it.
- **Retrospective patterns** (`sdmTMB_retro()`, Mohn's rho). A specification must not be tuned to
  make the retrospective look good.
- **Confidence-interval width.** Narrower intervals look like a better model, but the interval is
  only as good as the model behind it, and for these models it is not always trustworthy. Use it
  to describe the final index, not to choose it.
- **Agreement with an existing assessment index.** A plausibility check on shape; reproducing the
  old index is not the goal. The final report's bridging section (`bridging-section.qmd`)
  rescales both series to their overlap mean and flags years that moved more than
  `REVISION_TOLERANCE` (default 20 %); every flagged year needs an explanation (new data, late
  components, filters, family, domain), not a model change.
- **Robustness to the data** (`robustness-section.qmd`): whole-station subsampling within years,
  start-year peels, the terminal year without components that usually arrive late
  (`LATE_COMPONENTS`), and down-weighting a year with a known problem. Subsample stations, not
  rows: in a stacked class model a row is one class at one station. Down-weighting is a
  sensitivity with a recorded reason, never a way to tune the index.

## Comparing candidates fitted to different response scales

AIC and held-out log-likelihoods are only comparable between models of the **same response
variable** (comparability rule 2). A survey-index project often wants to compare across exactly
that boundary: a density response $\rho_i = B_i / A_i$ (catch per swept area) against raw catch
$B_i$ with a $\log A_i$ offset. As sdmTMB reports them the two are on different likelihood
scales, but the change-of-variable (Jacobian) correction puts them on one. Since
$\mathrm{d}B / \mathrm{d}\rho = A$,

$$\log f_\rho(\rho_i) = \log f_B(B_i) + \log A_i ,$$

and the correction applies **only to observations with a positive catch**. A zero contributes a
probability mass, $P(B_i = 0) = P(\rho_i = 0)$, which does not change under the transform. So, for
delta and Tweedie families alike,

$$\ell_\rho = \ell_B + \sum_{i:\, B_i > 0} \log A_i .$$

Apply it to the in-sample log-likelihood (and hence AIC) and, per held-out observation, to the
cross-validated log predictive density:

```r
# Add to a catch-scale log-likelihood to express it on the density scale.
jacobian_to_density <- function(log_area, positive) sum(log_area[positive])
# Per-observation version for cross-validated pointwise log-likelihoods.
jacobian_obs <- function(log_area, positive) ifelse(positive, log_area, 0)
```

Report raw and corrected columns side by side so the size of the artefact is visible. Uncorrected,
the catch-scale model gains $-2\sum \log A_i$ AIC units for nothing; with swept areas of a few
hundredths of a square nautical mile and a thousand positive hauls that is thousands of units,
enough to swamp any real difference.

Two checks make the correction trustworthy:

1. A standard delta-lognormal or delta-gamma fitted to $\rho$ without an offset and to $B$ with a
   $\log A$ offset is **the same model**: identical estimates, identical index, log-likelihoods
   differing by exactly $\sum_{B_i > 0} \log A_i$. Verify this once on the project's data.
2. Where all candidates can be fitted to the **same** response, do that instead. With an offset,
   a standard delta model on $B$ is the density model, so a family comparison fitted entirely on
   the catch scale needs no correction at all.

`sdmTMB_selection()` does not apply this correction; compute it from the table and the stored
fits.

## Prefer a Poisson-link delta family when swept area varies

In a standard delta family the sdmTMB `offset` enters the **positive component only**, so the
swept area cannot affect the probability of a zero catch: a short and a long haul at the same
place have the same modelled encounter probability. A Poisson-link delta model
(`delta_lognormal(type = "poisson-link")`, `delta_gamma(type = "poisson-link")`; Thorson 2018)
removes that limitation. Its first linear predictor is log group density, the offset enters it as
$n_i = \exp(\log A_i + \eta_{1i})$, the encounter probability is $p_i = 1 - \exp(-n_i)$, and the
expected catch is $\exp(\log A_i + \eta_{1i} + \eta_{2i})$, so effort drives both components. It
takes continuous catch weight; counts are not needed.

**Prefer the Poisson-link family when it fits at least as well as the alternatives** (corrected
cross-validated ELPD, then corrected AIC) **and converges with the structure every product
needs.** The reason is structural, not only statistical: it is the only delta parameterisation in
which the effort model is coherent for the zeros. Its extra structure makes convergence the
binding constraint, so it is not preferred if it fails `sanity()` where a standard delta passes.

**Tweedie with an offset is coherent too.** It has one linear predictor, so the offset scales
the mean $\mu_i = \exp(\log A_i + \eta_i)$, and the probability of a zero,
$P(Y_i = 0) = \exp\{-\mu_i^{2-p} / [\phi(2-p)]\}$, falls as swept area grows. It is therefore a
valid baseline beside the Poisson-link delta families, and it is the family of many existing
survey indices. **When a new index replaces an existing one, include the existing index's
family among the candidates**, so the bridging comparison (Step 4) can separate a change of
family from a change of data or domain. Tweedie's single linear predictor is also its limit:
covariates cannot act differently on occurrence and on positive catch.

Practical notes:

- **Predict at `offset = 0`** (one unit of swept area) so the prediction is a density and
  `get_index(area =)` scales it once. The encounter/positive split reported at that point is not
  interpretable — one square nautical mile is tens of times a typical haul, so $p$ saturates —
  only the product is.
- **The random-field structure may need to change with the family.** Under a Poisson-link the
  components mean different things (log group density and weight per group), and a spatial field
  that was estimable in one component of a standard delta model may collapse in the other. Re-run
  the random-field stage after changing family rather than carrying the old structure across.
- **It is a candidate to test, not a default.** In one benchmark (total biomass, same data and
  response, so AIC comparable) the Poisson-link delta-lognormal converged and passed `sanity()`
  but was 502 AIC units worse than the standard delta-lognormal; the indices differed little
  (median ratio 0.98, within ±9 % in the well-sampled years, larger in sparse early years), and
  the fit took about 20 % longer. Report such a result and keep the better-fitting family.
- When combining delta components in prediction code, use `est1 + est2` for the Poisson link
  and `plogis(est1) * exp(est2)` for a logit first component. `plogis()` on a Poisson-link
  `est1` gives a plausible-looking but meaningless map.

## Grid resolution

The prediction grid does not change the fit, but it changes the index (through how well the cells
follow the coastline and the depth limit) and it dominates the cost of prediction: the predicted
object grows with cells × years, and `get_index()` with bias correction is the step that runs out
of memory. Choose the **coarsest grid whose index is indistinguishable from the finer ones**:
predict the selected model on a ladder of cell sizes, compare the indices and the total grid area,
and report prediction time and object size beside them. A grid much finer than the mesh can
resolve adds cells, not information; a grid much coarser than the mesh cutoff starts to
misrepresent the domain boundary.

**Every stage gets three outputs**: the table, `plot(sel)` (the status-coded ranking), and
`plot(sel, type = "index", newdata = grid)`. The third is the one that matters most and is the
one most often skipped: *does this choice actually move the index?* A stage where the winner
and the runner-up produce the same index is a stage you can stop arguing about.

## Cost control: AIC first, CV on a shortlist

A cross-validated candidate costs `k` fits. Cross-validating a ten-candidate ladder at `k = 10`
is a hundred spatiotemporal fits, which is days, not hours. Rank on AIC first, then
cross-validate the top few:

```r
sel <- sdmTMB_selection(cands, data = dt_sel, ..., cache_dir = sel_dir,
                        cache_prefix = "fixed")                # cheap: 1 fit each
short <- best_candidate(sel, n = 3, by = "aic")
cv <- sdmTMB_selection(cands[short], data = dt_sel, ..., cv = 10, cache_dir = sel_dir,
                       cache_prefix = "fixed")                 # reuses those fits
```

Keep the same `cache_prefix` for the two calls. The cache holds the whole-frame fit and the
cross-validation in separate files per candidate, so the second call reuses the fits the ladder
already paid for and pays only for the folds.

The shortlist is defined by AIC rank and nothing else — no candidate is designated in advance
and none is exempt — so if the ladder is re-run with different covariates the shortlist follows
the evidence. Candidates far down the AIC table are not rescued by predictive performance, and
spending a day establishing that changes nothing.

## Which cross-validation asks which question

- **Random folds** (the default, `cv = k`) hold out scattered stations: this measures
  *interpolation* — predicting a station with others nearby in space and time.
- **Spatially clustered folds** (`fold_ids` from `blockCV::cv_spatial()`) hold out whole areas:
  this measures *extrapolation* into ground the survey did not cover that year. That is the
  harder test, and the relevant one for a model whose entire purpose is to integrate over a
  grid, including cells nobody sampled.
- **Leave-future-out** (`lfo = TRUE`) fits to years up to *t* and scores year *t + 1*. This is
  the question an assessment update actually asks, and it is the hardest one for a model with
  an AR1 field, whose terminal year sits at the end of the chain.

`sdmTMB_cv()` down-weights held-out rows to zero rather than deleting them, which is what keeps
every time step present for an `ar1`/`rw` field. Do not replace it with a loop that subsets the
data — deleting rows can empty a year and quietly change the model being validated.

Log-likelihood, RMSE and MAE do not have to agree, and where they do not the disagreement is
informative. Log-likelihood is sensitive to the whole predictive distribution, including the
zeros; RMSE is dominated by the largest catches, since it squares the errors; MAE weights every
station equally and is the most robust to the long right tail. A candidate that wins on
log-likelihood but not RMSE predicts the *shape* of the catch distribution well while missing
some large hauls — for an index built by integrating a predicted field, that is usually the
trade worth making.

## The assessment constraint on the spatiotemporal structure

Statistical fit is not the only criterion here. Total and length-group indices, read as
descriptions of the stock, use `spatiotemporal = "ar1"` and **no** year fixed effect. An index
that feeds a state-space assessment model — **SPiCT above all**, and also SAM or a state-space
JABBA — defaults to `spatiotemporal = "iid"` with **year as a fixed effect**
(`formula = value ~ 0 + factor(year) + ...`). Advise this whenever `ASSESSMENT_MODEL` is SPiCT,
without waiting to be asked.

Why: an `ar1` or `rw` field, a smoother on year (`s(year)`), or `time_varying = ~ 1` all borrow
strength across years, so each year's estimate is pulled towards its neighbours. That is
smoothing, and SPiCT already smooths: it treats biomass as a latent state with process error
(`sdb`) and the index as an observation of it with observation error (`sdi`). A pre-smoothed
index therefore

1. is **smoothed twice**, and SPiCT attributes too much of the variation to the latent state;
2. carries **autocorrelated observation errors**, which breaks the independence the OSA residual
   tests assume (Ljung–Box in `plotspict.diagnostic()`); and
3. has **understated inter-annual variability and standard errors**, so `sdi` is
   underestimated, `stdevfacI` is too small, and the advice confidence intervals are too narrow.

With an `iid` field and year as a fixed effect, each year's level is estimated from that year's
data alone, and its standard error — larger than under `ar1`, as it should be — goes to SPiCT as
`stdevfacI`. Let the assessment model separate process from observation noise.

If cross-validation prefers `ar1` for the assessment index, say so in the text and carry `iid`
anyway, with the reason — see the next section. If a year has too few positive catches for its
year effect to be estimated, report it and drop that year from the hand-off (SPiCT handles a
missing year) rather than returning to `ar1`. For an assessment model that is not state-space
(e.g. gadget3), the same independence argument applies to its likelihood, so prefer `iid` + year
there too; confirm with the assessment lead.

A third configuration is common in existing survey indices: **a year fixed effect with an AR1
field**. The year effect leaves the annual mean free, as in `iid` + year, while the AR1 field
correlates only the spatial deviations from one year to the next, which helps a sparsely sampled
year borrow its spatial pattern from its neighbours. The annual mean is not smoothed, so it
meets the assessment constraint; the cost is a parameter per year and an AR1 correlation that
can approach 1 when the year effect absorbs the common signal. Validate it beside the other
two (`validate.qmd` stage 4: "AR1 + year effect", read against "AR1"), and include it whenever
the index replaces one that used it. Build the year factor as a column (`fyear`), never as
`factor(year)` in the formula, when `extra_time` is used.

## When the carried-forward model is not the winner

This is common and legitimate: comparability across documents, an assessment requirement, or a
model simple enough to converge every year. **Record the gap, do not hide it.** Read the
difference from the table and state it, so the document says "AIC prefers X by N units; Y is
carried forward because …" rather than implying the choice followed from the selection.

```r
carried <- "Full model"
gap <- sel$table$deltaAIC[match(carried, sel$table$model)]
```

Note the idiom: matched **by label**, not by row position. The table is sorted by the metric,
so `sel$table$AIC[1] - sel$table$AIC[2]` is best-minus-runner-up regardless of which model you
meant, and it is negative by construction whichever way the comparison actually falls. The same
applies to correlation matrices and any other lookup in a rendered document: index by name, and
guard the lookup so a candidate that failed to fit produces a dash in a sentence rather than an
error at the end of a long render.

## Combining surveys and seasons

Surveys run in different seasons (an autumn ecosystem survey and a winter survey, say) can be
combined into one index or kept as separate seasonal indices. Settle four things, in order, and
record each in `ai/memory/`:

1. **The index year.** Decide which surveys share a time step and set
   `INDEX_YEAR_START_MONTH` / `INDEX_YEAR_LABEL` (`data-filtering.md`). The data report's
   index-year table shows the mapping; `ASSESSMENT_INDEX_TIMING` is a fraction of that year.
2. **Catchability.** Surveys differ in gear rigging, timing and behaviour of the stock, so give
   them a fixed catchability factor (`SURVEY_EFFECT: true` → `fsurvey`) and predict at a stated
   `REFERENCE_SURVEY`. It identifies only from years and areas the surveys share; read the
   `design_balance()` tables first.
3. **Spatial pattern.** If the stock is distributed differently in the two seasons, a
   survey-specific spatial deviation field lets each survey depart from the shared pattern:
   numeric indicator columns for the non-reference surveys in `spatial_varying`, **with the
   `fsurvey` fixed effect kept in the formula**. The deviation field has mean zero; without the
   fixed effect, the average catchability difference is forced into a penalised field. A factor
   in `spatial_varying` behaves differently between sdmTMB versions (the intercept column is
   now dropped automatically), which is why the template builds indicator columns. Treat the
   field as a sensitivity (`validate.qmd`, `run_survey_field`), like the barrier mesh.
4. **One index or two.** A combined index predicts at the reference survey. Separate seasonal
   indices predict the same fit once per survey and are separate assessment inputs with their
   own timing; never average them into one series after the fact.

## Stacked class models

Size-, sex- or maturity-class products (legal-size males, mature females, length groups) can be
fitted one class at a time, or as **one stacked model**: one row per station and class, the
response the class's catch, class-specific smooths (`s(depth, by = fclass)`) and class-specific
year effects (`time_varying = ~ 0 + fclass` with `time_varying_type = "rw0"`, or `fyear:fclass`).
It borrows strength between classes and gives all products one structure, which helps sparse
classes converge.

Its assumption is easy to miss: **the spatial and spatiotemporal fields are shared by all
classes**, so all classes are assumed to have the same spatial pattern, varying only in level
and depth response. That is doubtful for sexually or ontogenetically segregating species.
Alternatives, in increasing cost:

- class-specific spatial fields: `spatial_varying = ~ 0 + fclass` with `spatial = "off"` (each
  level then has its own field; leaving `spatial = "on"` duplicates the intercept field);
- separate fits per class (the index-wise default for length groups, `get_index_split()`);
- a multivariate model with correlated class fields, e.g.
  [tinyVAST](https://github.com/vast-lib/tinyVAST) or spatioTemporalIndices
  ([Breivik et al. 2021](https://nr.no/en/publication/1927756)), for abundance-at-length.

Build the stacked frame by expanding **every retained station** to every class with zeros for
absent classes, but only where the station's individuals were measured: a positive station
without individual data is missing from all classes (`data-filtering.md`). Compare a stacked
model with separate fits on the index each produces; they are fitted to different response
data, so AIC does not compare them.

## Caching and resumability

Selection is the slowest thing in the project, so it is the most likely to be interrupted.

- `cache_dir` writes **one `.rds` per candidate**. A failure on the last candidate then costs
  one candidate, not the whole ladder. Use a different `cache_prefix` per stage.
- `only = "<candidate name>"` computes just that candidate and reads the rest from cache. This
  is what lets a long ladder be spread across several R sessions: a large spatiotemporal fit
  can peak at several GB, and a dozen of them accumulating in one process exhausts memory, at
  which point candidates start failing for reasons that have nothing to do with the model.
- Free each fit between candidates in any hand-written loop (`rm(m); gc()`); `sdmTMB_selection()`
  keeps only the summary and the fit you asked it to keep.
- **Key each stage's cache to the settings it holds fixed.** Append a short hash of those
  settings (mesh cutoff, family, formula, fields, data version) to the stage's `cache_prefix`,
  so a changed upstream choice cannot silently reuse stale candidate fits. Leave the setting
  the stage *varies* out of its own key — otherwise changing `MESH_CUTOFF_KM` in the config
  invalidates the mesh ladder that chose it.
- **Compare candidate indices on one fixed selection grid**, independent of `GRID_KM`, and
  scale by that grid's cell area. Otherwise a grid change between renders moves every index and
  the comparison measures the grid, not the candidate.

See `rendering.md` for the render-side toggles and the screen-session discipline.

## What the document must end with

A short "Decision" section stating the chosen formula, family, spatiotemporal structure, mesh
cutoff and barrier choice; the evidence (which table, which metric, by how much); and — where
the choice was not the table's winner — why. Record it in `ai/memory/` as a decision. That
paragraph is what a reviewer reads.

## References

- Hastie, T., Tibshirani, R., and Friedman, J. 2009. The Elements of Statistical Learning: Data
  Mining, Inference, and Prediction. 2nd edn. Springer, New York.
  <https://doi.org/10.1007/978-0-387-84858-7>- Hurtado-Ferro, F., Szuwalski, C. S., Valero, J. L., *et al.* 2015. Looking in the rear-view
  mirror: bias and retrospective patterns in integrated, age-structured stock assessment
  models. ICES Journal of Marine Science, 72: 99–110. <https://doi.org/10.1093/icesjms/fsu198>
- Mohn, R. 1999. The retrospective problem in sequential population analysis: an investigation
  using cod fishery and simulated data. ICES Journal of Marine Science, 56: 473–488.
  <https://doi.org/10.1006/jmsc.1999.0481>
- Breivik, O. N., *et al.* 2021. Predicting
  abundance indices in areas without coverage with a latent spatio-temporal Gaussian model.
  ICES Journal of Marine Science, 78: 2031–2042. <https://nr.no/en/publication/1927756>
- Thorson, J. T. 2018. Three problems with the conventional delta-model for biomass sampling
  data, and a computationally efficient alternative. Canadian Journal of Fisheries and Aquatic
  Sciences, 75: 1369–1382. <https://doi.org/10.1139/cjfas-2017-0266>
- Vehtari, A., Gelman, A., and Gabry, J. 2017. Practical Bayesian model evaluation using
  leave-one-out cross-validation and WAIC. Statistics and Computing, 27: 1413–1432.
  <https://doi.org/10.1007/s11222-016-9696-4>
