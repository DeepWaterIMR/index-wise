# Commercial CPUE — the data and what makes them an index

A commercial catch-per-unit-effort (CPUE) index uses the fleet's own catch and effort records
as a relative abundance index, typically where surveys are sparse, short or do not cover the
fished component. It rests on one assumption: after standardisation, **CPUE is proportional to
the abundance of the fished component**, $\mathrm{CPUE}_t = q N_t$, with a catchability $q$ that
does not change over time. Everything below is about what breaks that assumption and how to
contain it. The model mechanics are in `cpue-models.md`; the workflow is in the
`index-cpue-data` and `index-cpue-model` skills. Good-practice reviews: Maunder & Punt
([2004](https://doi.org/10.1016/j.fishres.2004.08.002)) and Hoyle *et al.*
([2024](https://doi.org/10.1016/j.fishres.2023.106860)).

**Commercial data are not Biotic data.** Logbooks and sales notes come from the Directorate of
Fisheries through IMR's internal data services, not from the Biotic database, and BAIT does not
cover them. They are confidential at the record level (vessel identity, position, catch): the
same rules as for Biotic apply. Keep the raw extracts under the project's git-ignored
`data/source/`, commit only aggregates and model outputs, and never show individual vessels or
precise fishing positions in shared documents.

## Every commercial dataset needs its own treatment

**There is no generic reader for commercial data, and index-wise deliberately ships none.**
Catch-and-effort data differ by source, by country and by period, and the differences are in
the meaning of the fields, not only in their names:

- **Source.** Haul-level electronic logbooks, daily or trip-level paper logbooks, sales notes
  (landings per trip), observer data, VMS/AIS and gear-position services each record a
  different unit, a different effort, and catch at a different stage (caught, retained,
  landed).
- **Country.** Each national authority defines its own reporting obligations (which vessels,
  which gears, which fields), formats, species and gear codes, area systems and vessel
  identifiers. Records of foreign vessels fishing in national waters, or of national vessels
  abroad, may sit in another country's system or be missing. Combining nations means
  reconciling definitions first, never stacking tables.
- **Period.** Within one source, rules change: logbook obligations extended to smaller vessels,
  new mandatory fields, changed code lists, paper replaced by electronic reporting, revised
  position or duration conventions. A field with the same name can mean something different
  before and after such a change.
- **Fishery.** The same field can describe different quantities in different fisheries (a
  duration that is the soak time in one trap fishery and only the hauling operation in
  another; "effort" as traps, hauls, hooks or hours).

So each CPUE project writes **bespoke, documented data treatment** for its own extract, as part
of `index-cpue-data`:

1. Obtain the reporting instructions and code lists that applied in every year of the series,
   and record their source and version in `ai/memory/`.
2. Map the extract to the record schema of `cpue.qmd` explicitly, field by field, with the
   meaning and unit of each mapped field and the years it is valid for.
3. Identify every change of source, obligation, format or definition, and treat each as a
   potential break in catchability (`cpue-models.md`, *Data-source breaks*).
4. Check the result against independent totals (landings) before any model is fitted.

The record schema, the filter cascade and the models in index-wise start **after** this step.
Do not reuse another stock's or another country's data treatment without checking each of
these points again.

## Why CPUE is not abundance

Catch rate tracks abundance only if fishing samples the stock in a stable way. Fishers do not:
they search for aggregations, move with them, share information, and change gear, vessels and
behaviour. The common consequences:

- **Hyperstability** — CPUE stays high while the stock declines, because effort concentrates on
  the remaining aggregations or search becomes more efficient. It is the typical bias: across
  297 series compared with surveys, CPUE was on average hyperstable (Harley *et al.*
  [2001](https://doi.org/10.1139/f01-112)). Standardisation does not remove it; a spatial model
  that weights areas by their size, not by their effort, reduces it.
- **Hyperdepletion** — the opposite, e.g. when the fished area expands into poorer grounds, or
  when unfished areas are assumed to behave like fished ones (Walters
  [2003](https://doi.org/10.1139/f03-152)).
- **Effort creep** — gear, electronics and skills improve, so the same nominal effort catches
  more. A year effect cannot separate creep from abundance; only covariates that measure it
  (vessel, gear specification, engine power) can, and only partly.
- **Targeting and multi-species fishing** — a record's catch of the target depends on whether
  the trip targeted it. Zero or low catches of a non-targeted trip are not information about
  the stock.
- **Management and market changes** — quotas, individual vessel quotas, closures, season
  limits, minimum landing sizes and prices change where, when and how fishers fish, and
  therefore $q$. A management change is a candidate break in the series.

Record every such change in the project's `ai/memory/` with its year. A CPUE index that spans a
known break either models it (a catchability step, a separate series in the assessment) or is
split there.

## Data sources and their unit of observation

| Source | Unit | Effort | Position | Typical issues |
|---|---|---|---|---|
| Electronic logbooks (ERS) | haul / set | gear-specific (traps, soak or hauling time, trawl time, hooks) | start and stop coordinates | coverage depends on vessel length and year; duration fields mean different things by fishery; positions sometimes repeated or reported later |
| Aggregated (paper) logbooks | day or trip | summed over hauls | daily position or statistical square | pre-ERS years; coarser unit; may overlap ERS in transition years |
| Sales notes (landings) | trip / landing | trips (LPUE) | statistical location only | no gear effort; landed, not caught, catch; several notes per trip |
| VMS / AIS / gear-position services | position fixes | time at fishing speed | precise | coverage by vessel size and year; matching to hauls needed |

Rules that follow from the table:

1. **One unit of observation per index.** Do not mix hauls with daily or trip records in one
   model without aggregating to a common unit. When the source changes (aggregated logbooks →
   ERS), either aggregate the new source to the old unit, model the source as a catchability
   effect estimated from overlapping years, or split the index into two series with separate
   catchabilities. Check first whether the "overlap" is genuinely independent: aggregated
   logbooks after a transition are often daily sums of the same ERS records.
2. **Know what the effort field measures.** For a trap fishery the ERS duration can be the soak
   time or only the hauling operation; for trawls it is towing time. Read the reporting
   instructions and the data, and name the variable after what it is.
3. **Positions.** Use the position that is closest to where the gear fished (stop position for
   hauled gear, matched gear or VMS positions where available), state the rule, and flag
   repeated or implausible positions. Positions in the statistical grid alone (sales notes)
   support area factors, not spatial fields.
4. **Reconcile with landings.** Compare the logbook catch per year with the landed catch of the
   same fishery and area. The coverage share tells how representative the logbook fleet is,
   and a falling share is a warning that the index describes a shrinking subset of the fleet.

## Preparing the record frame

The steps below are the ones every CPUE compilation needs; `index-cpue-data` turns them into a
document, and `R/cpue_helpers.R` provides the filter cascade and summaries.

- **Species and gear.** Keep the target species and the gear the index describes. Different
  gears are different fisheries, not a factor to standardise away, unless the data show the
  same vessels using both on the same grounds.
- **Vessel identity.** Use a stable identifier (call sign or registration), check for vessels
  that change length, tonnage or engine power under the same identifier, and give a replaced
  vessel a new identifier from the year of the change (a change of more than ~2 m length or
  ~500 hp is a practical threshold; check the distribution).
- **Plausible ranges.** Remove records with missing or zero effort, missing vessel, impossible
  catch or effort (unit errors such as grams for kilograms), and positions outside the fishery.
  Prefer documented thresholds from the fishery over percentiles; every threshold becomes a
  sensitivity run.
- **Positive catches.** Logbooks of a directed fishery rarely record zero catches, and when they
  do, a zero may mean "not targeted". Model positive catch by default; use a zero-inclusive
  family only where zeros are recorded systematically and mean "fished here, caught none".
- **Core fleet.** Vessels with very few records or years contribute little to the year effects
  and much to their noise. Filter on years active, records per year and lifetime records; keep
  the thresholds in the configuration, report how many vessels, records and how much catch each
  removes, and vary them in the sensitivity analysis.
- **Covariates.** Depth (from bathymetry when the logbook field is missing or zero), day of
  year or day within the vessel's season, time of day, vessel length or engine power, gear
  specification, soak or tow time. **Avoid covariates that trend with time by construction**,
  such as "years of experience in this fishery": their effect is estimated from the same change
  over time as the year effect and can absorb part of the abundance trend. If used, show the
  index with and without them.
- **The terminal year is usually incomplete.** At assessment time the current season is not
  over; months fished early in the season can have different catch rates. Either use complete
  seasons only, or standardise for season and test the effect with a final-month retrospective
  (refit earlier years with their data cut at the same month).

## What the index represents

State it in the report: the standardised catch rate of **the selected fleet** fishing **the
selected gear** in **the selected area and season**, at **reference conditions** (one unit of
effort, a reference season day, an average vessel). It is a relative index of the fished
component — often legal-size males in crab fisheries — not of the whole stock. When it enters an
assessment with a survey index, the two measure different components and can legitimately
diverge; compare their trends, not their levels.

## References

- Harley, S. J., Myers, R. A., and Dunn, A. 2001. Is catch-per-unit-effort proportional to
  abundance? Canadian Journal of Fisheries and Aquatic Sciences, 58: 1760–1772.
  <https://doi.org/10.1139/f01-112>
- Hoyle, S. D., *et al.* 2024. Catch per unit effort modelling for stock assessment: a summary of
  good practices. Fisheries Research, 269: 106860.
  <https://doi.org/10.1016/j.fishres.2023.106860>
- Maunder, M. N., and Punt, A. E. 2004. Standardizing catch and effort data: a review of recent
  approaches. Fisheries Research, 70: 141–159. <https://doi.org/10.1016/j.fishres.2004.08.002>
- Walters, C. 2003. Folly and fantasy in the analysis of spatial catch rate data. Canadian
  Journal of Fisheries and Aquatic Sciences, 60: 1433–1436. <https://doi.org/10.1139/f03-152>
