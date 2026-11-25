# Index level versus trend

A survey index enters an assessment as a **relative** index: SPiCT, SAM and gadget3 estimate its
catchability, so a constant factor on every year is absorbed and carries no information. What
the assessment reads is the **trend**. Every sensitivity, influence and model comparison should
therefore be judged on the trend, with the level reported beside it but not mixed into it.

## Why the level cannot be trusted

The level of a model-based index is set by choices that are arbitrary for the assessment:

- the **prediction references** — month, survey series, gear, catchability covariates — at
  which the grid is predicted (`REFERENCE_MONTH`, `REFERENCE_SURVEY`, `REFERENCE_GEAR`,
  `CATCHABILITY_REFERENCE`);
- the effective swept width and the effort convention;
- **shared parameters** that one survey can move for every year at once.

The last one is the trap. A month factor (or smooth) is estimated from the surveys that fish in
each month; when one series dominates a month, the month effect is in practice that series'
catchability. Leaving the series out, or adding a series, then moves the month effect, and the
index predicted at that month shifts by the same factor in **every** year — including years
before the series existed.

Example (tusk, ICES 1–2, 2026): the grid was predicted at the most sampled month, August, which
was mostly one Barents Sea ecosystem survey, while most of the predicted biomass was on the
coast sampled in October. Leaving that survey out halved the index in every year (the August
effect fell from 0.41 to −0.20 on the log scale), giving a leave-one-out influence of 0.46,
while the trend changed by only about 11 %. Predicting at October removed the dependence.

## Rules

1. **Choose the reference month where the main survey samples the bulk of the stock**, not by
   default at the most sampled month, and take the index timing (`ASSESSMENT_INDEX_TIMING`)
   from it. Do the same for the reference survey and gear. State the choice and its reason in
   the fit and report documents.
2. **Report a level ratio and a trend change separately** for every alternative index
   (leave-one-survey-out, cruise influence, sensitivity refits, mesh or family comparisons):
   - level ratio: the geometric mean of $I^{alt}_t / I^{base}_t$;
   - trend change: the mean absolute difference between the two indices after each is divided
     by its own mean (or geometric mean) over the common years.
   A large level ratio with a small trend change is a reference or shared-parameter effect, not
   a data problem.
3. **Recognise the signature.** An influence that is the same ratio in every year, including
   years before the left-out series started, is a level shift through a shared parameter.
   Check the month (and series, gear) effects with and without the series before suspecting the
   data.
4. **Do not present the absolute index as a biomass estimate** or use it as a prior on
   catchability. Plot indices mean-scaled when comparing them.
5. **Month and survey terms are confounded** when each series fishes in its own months. Treat
   the month term as a catchability term, and consider a cruise-series factor
   (`model-selection.md`, *Fixed effects*) predicted for the reference survey instead.

Related: `model-selection.md` (prediction references, fixed effects), `influence-diagnostics.md`
(survey-level signal), `assessment-index-handoff.md` (timing).
