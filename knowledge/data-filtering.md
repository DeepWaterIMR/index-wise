# Data filtering — making catches quantitative

**This is the single most important file in the pack.** A spatiotemporal index is only valid
if every retained record represents the intended *standardised, quantitative* bottom-trawl
sampling unit with a real swept area, and if stations with no catch of the target species are
kept as **true zeros**. Incorrect keys, catchsample aggregation, `gearcondition`,
`samplequality`, `stationtype`, or duplicates silently corrupt the index. Survey-specific
departures from this template require an explicit methodological decision.

The logic below is distilled from the background material listed in `workflow.md` (the
IMR-internal reference project's data-compilation notebooks and data report). Access the
Biotic database through BAIT (`biotic-connect`); the tables are `stnall` (station catches),
`indall` (individual/length records), `mission`, and the `gearindex`/`taxaindex` lookups.

## Station-level filter

Apply to `stnall`. `filter_sp` holds the Norwegian `commonname` value(s) of the target
species (confirm via BAIT's `taxaindex` — don't guess).

```r
last_complete_year <- as.integer(format(Sys.Date(), "%Y"))
obsolete_gear_codes <- unique(stats::na.omit(obsolete_gear_codes))
accepted_gearcondition <- c(1, 2) # inherited reference-workflow rule; verify for each survey

stn <- stnall |>
  dplyr::filter(
    gearcategory == "Bottom trawls",
    missiontypename %in% c("Forskningsfartøy", "Leiefartøy"),  # research + charter vessels
    startyear > 1980,
    startyear < last_complete_year,                            # drop the incomplete current year
    !is.na(distance),
    latitudestart > 0,
    gearcondition %in% accepted_gearcondition,
    is.na(stationtype) | stationtype %in% c("1", "3", "9", "13"), # keep-list: unflagged, 24-h, regular and additional stations
    distance >= 0.3, distance <= 5,   # trawl haul length in nautical miles
    is.na(gear) | !gear %in% obsolete_gear_codes, # retain missing; drop obsolete/non-standard trawl types
    dplyr::if_else(
      !is.na(.data$cruiseseriescode) & .data$cruiseseriescode == "23",
      .data$samplequality %in% 1:2,
      .data$samplequality %in% 1
    )
  ) |>
  dplyr::collect() |>
  # sample-quality is conditional on the cruise series:
  dplyr::filter(
    dplyr::if_else(
      !is.na(.data$cruiseseriescode) & .data$cruiseseriescode == "23",
      .data$samplequality %in% 1:2,
      .data$samplequality %in% 1
    )
  )

if ("missionid" %in% names(stn)) {
  stn <- stn |>
    dplyr::mutate(haul_id = paste(missionid, serialnumber, sep = "_"))
} else {
  stn <- stn |>
    dplyr::mutate(haul_id = paste(missiontype, startyear, platform, missionnumber,
                                  serialnumber, sep = "_"))
}
```

Build the station roster independently of target catch weight. Validate missing or inconsistent
target catch records after joining the target species onto the retained stations; otherwise empty
catch stations are lost before they can become true zeros.

A row in `stnall` is a catchsample record. In BES, use `missionid + serialnumber` as the
fishstation key. The native NMD Biotic key comprises `missiontype`, `startyear`, `platform`,
`missionnumber`, and `serialnumber`. `missionid` is a BES convenience field. Do not build keys
from `cruise`, `platformname`, or `callsignal` without proving uniqueness.

One fishstation can contain several catchsamples or catch parts for the same species. Inspect
`catchsampleid`, `catchcategory`, `catchpartnumber`, product fields, raising fields, and comments
before summing. Some rows are disjoint and additive; others are nested or alternative
representations. Rare multisampler workflows can use separate `serialnumber` values for bags and
one shared `station` for the physical haul. Combine those records only when survey design, time,
position, depth sequence, and comments support that interpretation.

### What the tags mean

- **`gearcondition`** — the NMD field describes gear condition after the haul. The inherited
  reference workflow retains codes 1 and 2, but this is not a universal ordinal cutoff. Decode
  observed codes and justify `accepted_gearcondition` from the survey protocol or a verified
  reference table. Code 2 may be retained for some surveys.
- **`stationtype`** — use a **keep-list**, not a drop-list: missing (an ordinary unflagged station, ~70 % of rows), `1` (part of a 24-hour station), `3` (gear trial that is also a regular fish station), `9` (regular fish station) and `13` (additional, preselected station). A drop-list of `2`, `A`, `C`, `E` (gear trial, closed-area documentation, special purpose, purse seine/blue whiting) lets the multi-codend codes `4`–`8` through: a multi-bag haul then enters as several hauls with partial catches (seen in a 1995 research cruise). Codes are decoded in BAIT `knowledge/quality-codes.md`; extend the keep-list only for a documented survey-specific reason. Missing values are retained explicitly because a lazy DuckDB filter translates `stationtype %in% ...` to SQL, where `NULL` values would otherwise be dropped.
- **`samplequality`** — code 1 denotes deployment at a preselected position with normal gear
  operation. Code 2 denotes deployment on an acoustic registration or other information about
  fish, with normal gear operation when sensors were used. It is targeted sampling, not simply
  lower or “acceptable” quality. The inherited workflow keeps code 1 generally and codes 1–2 for
  **coastal cruise series 23**. Retain code 2 only when its targeting mechanism is compatible with
  the estimand and document the decision.
- **`distance` 0.3–5 nmi** — very short or very long hauls are unreliable for swept area.
- **`missiontypename`** — keep research and charter vessels only.
- **`last_complete_year`** — calculate this scalar in R *before* the lazy query. Calling a date-extraction function inside a DuckDB filter can be translated as invalid SQL rather than a year literal.
- **`obsolete_gear_codes`** — remove missing values from this small R vector before filtering. The explicit `is.na(gear) | ...` retains a missing gear value, matching the post-collection R semantics; SQL would otherwise drop it.

Decode quality fields through BAIT's `knowledge/quality-codes.md`. Reference lists are
extensible; never infer an unfamiliar numeric code from its order.

### Cruise identity, legacy SPD duplicates and documented exclusions

- **Cruise numbers are not unique.** The same cruise number has been used by two vessels in the
  same year. Any cruise-level operation (exclusion, influence screen, relabelling) keys on
  `platformname` (or `platform`) **and** `cruise`.
- **SPD files and Biotic overlap.** Some legacy SPD cruises were later entered into Biotic under
  other serial numbers, often as cruise series `Other`, so one tow appears twice (the same catch,
  depth and density). Match by position and start time with `RstoxUtils::match_spd_biotic()`
  (defaults ≤ 1 km and ≤ 3 h; SPD start times can be offset from NMD by about 2 h), keep the
  Biotic copy, give it the SPD cruise series, and drop the matched SPD cruises with
  `RstoxUtils::drop_spd_duplicates()`.
- **Documented exclusions** go in `config.yaml` `EXCLUDE_CRUISES` (platform + cruise + reason)
  and are applied in the compile step, never as an ad-hoc filter in a later chunk. Use them only
  after the influence workflow (`influence-diagnostics.md`) shows that no general rule works.

### Swept width and density columns

- Record the swept width assumed for every gear and survey. Indices computed with another width
  differ by a constant factor (25 m vs 80 m gives ≈ 3×); align widths before comparing with a
  historic index.
- When models use `EFFORT: offset`, the density column is not used by the model, but still check
  `density == catch / swept_area` after compilation. A mismatch (seen in a length-group product)
  reveals an allocation bug that will surface later in maps, screens and influence diagnostics.

### Russian data — INCLUDED by default

Unlike `ref-index-paper` (a public showcase that *excluded* Russian data), **this template
includes Russian data by default**, because the northern surveys need it for full spatial
coverage. Offer exclusion only as an explicit opt-out. If the user opts out, filter
`!nation %in% c("140", "90")` and clip the prediction grid to exclude the Russian EEZ.

## True absences (zeros)

For each retained station, the response for the target species is the summed catch there; a
station where the species was **not** caught is a real **zero**, not a missing value. Build the
response by joining the species catch onto the *full set of retained stations* so absences are
preserved. Absences are what let the binomial part of `delta_lognormal()` estimate presence
probability. Never drop zero-catch stations.

A missing target record is a zero only when catch recording was complete. Partial or unresolved
catchsample records remain missing until reviewed.

## Duplicates — detect and remove

The Biotic database can contain duplicate or inconsistent records (e.g. the same haul entered
twice, or length-sample totals exceeding the catch). Flag haul ids where the length sample exceeds
the catch and drop them; write a report to `ai/review/` for inspection.

```r
dupe_ids <- stn |>
  dplyr::filter(commonname %in% filter_sp) |>
  dplyr::group_by(cruiseseriescode, haul_id, commonname) |>
  dplyr::reframe(
    catchweight       = sum(catchweight, na.rm = TRUE),
    catchcount        = sum(catchcount, na.rm = TRUE),
    lengthsampleweight = sum(lengthsampleweight, na.rm = TRUE),
    lengthsamplecount  = sum(lengthsamplecount, na.rm = TRUE)
  ) |>
  dplyr::filter(catchcount < lengthsamplecount | catchweight < lengthsampleweight) |>
  dplyr::pull(haul_id)

stn <- dplyr::filter(stn, !haul_id %in% dupe_ids)
```

This diagnostic detects impossible length-sample totals; it does not prove that repeated
catchparts are duplicates. Resolve catchsample logic before applying it.

## BES vs SPD files

Historical data used to live in **SPD files** (e.g. `Barentshavtokt`, `Svalbardtokt`,
`Blakveite_prosjektet`). As records are added to the Biotic database, the SPD files become
**obsolete**. When binding SPD data to BES data:

- Drop SPD years/series that are **already in Biotic** (avoid double-counting).
- Tag the source (`source = "NMD"` for Biotic, `source = "SPD"` for legacy) for traceability.
- **For southern or coastal species, SPD files add little** — suggest using BES only and skip
  the SPD documents entirely.

## Swept-area density (the response)

Aggregate catch and swept area to the same sampling unit before division. Sum additive
numerators and denominators, then calculate density; do not average row-level densities.

Convert catch to density per swept area. The default template policy uses one common effective
width for all trawls:

```r
stn <- stn |>
  dplyr::mutate(
    gear_width    = 25,                          # metres; common effective width for all trawls
    swept_area    = swept_area_nmi2(distance, gear_width),  # nmi²: distance × width / 1852
    rho_biomass   = biomass / swept_area,      # kg   · nmi⁻²
    rho_abundance = count   / swept_area       # n    · nmi⁻²
  )
```

Keep `swept_area` in the compiled data even when the model uses densities: `EFFORT: "offset"`
models catch with `log(swept_area)` as offset, and the Step 2 scale check needs both. Do the
unit conversion only through `swept_area_nmi2()` (project `R/index_helpers.R`); see
`sdmtmb.md` *Effort and the index scale*.

### Gear width is a documented simplification

Use a common 25 m effective width for all trawls when the project adopts the simplified policy.
If more than one major gear type is represented, keep `geartype` in the spatial GLMM as a fixed
effect so the model can estimate systematic gear differences. Revert to gear-specific widths
only if diagnostics show that the common-width assumption is inadequate.

## Index year

The model's time step is the **index year**. It equals the calendar year unless the surveys
that belong together straddle New Year: an autumn survey and the following winter survey, or a
season from July to June. Set `INDEX_YEAR_START_MONTH` (the month an index year begins) and
`INDEX_YEAR_LABEL` (`"start"` or `"end"`: which calendar year names it):

| Design | `START_MONTH` | `LABEL` | Autumn Y | Winter Y+1 |
|---|---|---|---|---|
| Calendar year | 1 | – | Y | Y+1 |
| Season July–June, named by its start | 7 | `"start"` | Y | Y |
| Season July–June, named by its end | 7 | `"end"` | Y+1 | Y+1 |

`index_year()` computes it from `startyear` and `month`. Keep `startyear` (calendar) beside
`index_year` in the compiled data, label every model figure by index year, and use index years
for every year-specific setting (skipped years, down-weighted years, the previous index).
Mixing the two conventions puts a setting one year off without any error.

## Individual data: missing is not zero

Size-, sex-, maturity- and length-based products split a station's catch using its measured
individuals. A positive station **without** measured individuals has an unknown split. It stays
in the total product and must never be a zero in the class products. Zero-filling it is the
common error: a join of length groups onto stations followed by `tidyr::complete(fill = 0)` or
`replace_na(share, 0)` silently turns such stations into zeros at every length, and biases the
class indices low in years with incomplete sampling.

1. Record `n_measured` (measured target individuals per haul, 0 when none) in Step 1.
2. Report per index year the share of positive hauls and of catch without measurements
   (`length_coverage()`); `<stock>-3-data.qmd` shows the source of each haul's share in its
   *Fishable share and length coverage* figure.
3. **Template default: impute and flag.** `add_fishable_biomass()` in
   `R/compile_functions.R` gives an unmeasured positive haul the biomass-weighted mean share of
   the same survey, else of the same cruise series and year, else of the cruise series, and
   records the source in `fishable_imputed` (`measured`, `survey mean`, `series-year mean`,
   `series mean`, `none`). Use the same hierarchy and flag for any other class product. The
   alternative, when imputed hauls carry much of the catch, is to drop those hauls from the
   class products only (never from the total), and say so in the data report.

4. Raise measured individuals to the catch (`catchcount / lengthsamplecount`); summing the
   measured individuals is correct only when every individual was measured.

## Data that arrive after the assessment

Some components are routinely incomplete in the terminal year: another nation's vessel, a
charter vessel, a late-entered survey. Ask during scaffolding, set
`LATE_COMPONENTS: {column: ..., values: [...]}`, and let the data report show their haul counts
in recent years. Decide with the assessment lead whether the terminal year is used as it is
(wider uncertainty, revised next year) or the component is excluded from the whole series; the
robustness section shows how far the terminal year moves without it. Including a nation's data
by default (as for Russian data above) does not settle when those data arrive.

## Depth

Fill missing or invalid bottom depths from GEBCO bathymetry:

```r
stn$depth <- ggOceanMaps::get_depth(stn, bathy.style = "rc", bind = FALSE)
```

## Own-data contract (non-Biotic surveys)

Data that do not come from the IMR Biotic database skip Step 1's Biotic extraction but must
reach Step 2 in the same form: one row per sampling unit (haul), true zeros included, already
qualified as quantitative catches by the data owner's rules. Record those rules in the data
report and in `ai/memory/`.

| Column | Content |
|---|---|
| `haul_id` | Stable sampling-unit key, unique per row |
| `year`, `month` | Integer survey year and month |
| `lon`, `lat` | Decimal degrees, WGS84 (Step 2 converts to `X`/`Y` in km) |
| `depth` | Bottom depth in metres, positive; fill gaps with `ggOceanMaps::get_depth()` |
| `geartype` | Gear category kept as a fixed effect when more than one is present |
| `swept_area` | nmi² |
| `rho_biomass`, `rho_abundance` | kg · nmi⁻² and n · nmi⁻²; zero for hauls without the species |

Apply the same rules as above: sum numerators and denominators to the haul before dividing,
document the effective gear width, and clip stations to the study-area polygon.

## Spatial domain

Keep stations inside the study-area polygon; if Russian data are excluded, clip the Russian
EEZ. These GIS files are **user-supplied** and live only in the project's `data/` — never in
the template.
