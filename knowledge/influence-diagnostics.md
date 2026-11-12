# Influence diagnostics — which hauls and cruises drive an index value?

Use this when one index year (or a short run of years) looks implausible: a peak the stock
dynamics cannot produce, a jump that coincides with a survey change, a value far outside the
neighbouring years' intervals. The functions are in sdmTMBexperiments (≥ 0.1.9); the template
wires them into `docs/<slug>/influence-section.qmd` (`include_influence: true`).

Lessons from the redfish benchmark (second index-wise project, 2026): an apparent stock peak in
one year was an unrepeated, intensive sampling of a high-density slope area by a single
auxiliary cruise. No single haul caused it, no haul-level rule removed it, and the only clean
fix was a documented exclusion of that cruise.

## 1. Locate the anomaly in space — `index_by_region()`

Split the plug-in index by a region column of the prediction grid (subareas, depth bands,
inside/outside a survey footprint). Look at each region's share of the year's index and its
ratio to its own mean (`plot(x, type = "relative")`). A peak carried by one region, which is
also unusually well sampled that year, points to a coverage artefact. Compare the number of
hauls per region and year with the region split.

## 2. Screen cheaply — `density_share()`

Leave-one-out refits are expensive. Screen first with each haul's or cruise's share of the
year's summed density. Screens that worked: hauls — the two largest shares per year plus any
share ≥ 0.05; cruises — the three largest per year plus any share ≥ 0.1. That leaves roughly a
third of the cruises and a few per cent of the hauls.

- **Cruise identifiers must include the platform.** Cruise numbers are reused by different
  vessels (the same number has been used by two vessels in the same year). Build
  `paste(platformname, cruise)` and use it everywhere: screens, leave-out, exclusions.

## 3. Refit without each candidate — `sdmTMB_leave_out()`

Reuses the mesh and every model setting, warm-starts from the full fit, and keeps years without
data as `extra_time`. Two levels:

- **Hauls** — answers "is it one extreme tow?". In practice influential hauls were short tows
  (well under the standard tow length) in years with sparse coverage: a moderate catch becomes a
  high swept-area density. Per-haul influence of the hauls behind a collective anomaly was small
  (≈ 0.05 each), so a per-haul rule would not remove it.
- **Cruises** — answers "is it one survey?". Raw `influence ≥ 0.1` mostly flags the main survey
  of each year, which is expected. **Leverage** (`influence / haul_share`) separates the problem
  cruises: flag `influence ≥ 0.1` and `leverage ≥ 2` (`plot(x, type = "leverage")`). Flagged
  cruises were one-off or auxiliary cruises covering areas that few other cruises sample
  (continental slope, coast), often with few positive hauls.

Model structure changes how an anomaly propagates, so report both:

- `iid` spatiotemporal field + factor year: nothing links the year to its neighbours, so that
  year's field absorbs the whole anomaly.
- `ar1` field, no year effect: the anomaly is damped in its year but spreads into the
  neighbouring years (here ±3 years changed by 10–18 %).

Cache the influence results computed **before** any exclusion and document from that cache;
the post-exclusion fit no longer contains the evidence.

## 4. Decide with scenarios — `sdmTMB_data_scenarios()` + `peak_ratio()`

Refit under general rules and under the named exclusion, on the same mesh, and compare the
peak (`peak_ratio(x, year)`: the year divided by the mean of its neighbours) and every other
year (`plot(x, type = "ratio")`). Scenarios that use their own grid (e.g. restricting the
domain to areas sampled every year) are compared with `type = "scaled"` or `peak_ratio()`.

Decision policy (agreed with the assessment lead):

1. **Prefer a general rule** that removes the anomaly without distorting other years.
2. **A named exclusion is acceptable only when no general rule works**, and is documented with
   the scenario table and figure in the report. Put it in `config.yaml` `EXCLUDE_CRUISES`
   (platform + cruise + reason), never as an ad-hoc filter in a chunk.
3. Things that did **not** work as general rules:
   - **Haul-level rules** (drop or cap densities above the 99.5–99.9 % quantile, minimum tow
     length): they cannot remove an effect that builds up over many moderate hauls.
   - **Minimum tow length above ~1 nmi**: the standard tow length changed over time (about
     1.5 nmi in the 1990s, about 1 nmi after 2000), so the rule removes most recent hauls.
   - **Dropping a whole cruise series** (e.g. `Other`): removes the anomaly but shifts many
     other years by 10–40 %.
   - **Dropping a gear** because it looks commercial: ask the survey experts first. A large
     cod trawl used in early deep-water projects is a legitimate survey gear.
4. Check the station metadata of the candidate before deciding: `stationtype`, `samplequality`,
   `gearcondition`, cruise purpose, gear, and the swept width assumed for it. Normal metadata
   means the hauls are valid observations and the issue is coverage, not data error.

## 5. Survey-level signal — leave one survey series out

`sdmTMB_leave_out(fit, id_col = "cruiseseries")` shows which series carries the compiled
index. One dominant winter survey changed the index ≈ 2.7 times on average when removed, while
every other series moved it by ≤ 10 %: a single-survey dependence worth stating in the report.
A series nested in a combined series (e.g. one part of a slope survey that also exists as
north + south) should be dropped from the comparison, not shown twice.

## Reporting checklist

- Region split figure and haul counts per region × year around the anomaly.
- Screens used (thresholds), number of candidates, all refits' `sanity()` status.
- Leverage figure with flagged cruises, and what each flagged cruise sampled.
- Scenario table (peak ratio and effect on other years) and the decision with its reason.
- `EXCLUDE_CRUISES` entries quoted in the data section of the report.
