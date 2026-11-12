# Data documents — fixed structure

The data step produces **three documents per stock** in `docs/data/`. Their names, section
headings, figures and tables are fixed so that every project looks the same and an agent does
not invent a new layout each time. Adapt the *content* (text, interpretation, stock-specific
exceptions), not the structure. `<stock>` is `STOCK_SLUG` in `config.yaml` (default: the
species slug; for split domains, e.g. `atlantic-halibut-n62`).

| File | Title / subtitle | Role |
|---|---|---|
| `docs/data/<stock>-1-summary.qmd` | "<Species> — <area> survey index" / "Summary of the index calculation" | Abstract, purpose, document list, AI statement, overview of data, model and indices. Model and index sections are placeholders until Step 4 is done. |
| `docs/data/<stock>-2-survey-selection.qmd` | "<Species> — <area> survey selection" / "Step 1 of 2 · survey selection" | Which surveys, hauls and catch records enter the index and why. Runs the compilation and saves `compiled-data.rds`. |
| `docs/data/<stock>-3-data.qmd` | "<Species> — <area> data" / "Step 2 of 2 · data report" | Describes the compiled data: positions, depth, response distributions, trawl parameters, length–weight and length products, diagnostics. |

The number in the file name is the reading order. Model documents (fit, validation, final
report) follow under `docs/data-report/`.

## `<stock>-3-data.qmd`

Explains and shows the station-based and length-based data that enter the sdmTMB models; it
does not repeat survey selection (stock area, filter, surveys, gear tables, timing).

1. **Purpose** — what the compiled data contain and which responses (total biomass and the
   length-based product, e.g. fishable biomass ≥ `OVER_CM`) are fit to be modelled.
2. **Data** — *Data collation* with a Mermaid flowchart (stnall → haul roster with true zeros →
   total biomass; indall → raised lengths → weight at length → length share); *Station-level
   data* (catch summed over catch samples, density formula with `GEAR_WIDTH`; until the model
   response is decided, swept-area biomass density is used); *Individual-level data* (cm
   conversion, `LENGTH_LIMITS`, raising factor n/m); *Length-based data* (share formula,
   predicted weight at length, imputation hierarchy for positive hauls without lengths, which
   avoids false zeros from surveys that weighed but did not measure the catch; link to the
   *Fishable length* section of `docs/background/stock-background.qmd` and to `ai/tests/test-fishable-biomass.R`).
3. **Analysis**
   - *Dataset overview*: metric table (station and individual level), responses by cruise
     series, and *Response distribution* (histogram of positive densities, log x, zero share per
     product).
   - *Station-level data*: density map of both products; *Prediction region*
     (`build_stock_region()`: concave hull of positive hauls, `REGION_BUFFER_KM`,
     `REGION_CONCAVITY`, cut to the stock area plus buffered positives; written to
     `PREDICTION_REGION_FILE`; map and the share of hauls inside); annual share of positive
     hauls and mean density; *Tow distance* (distance by year and gear type, jittered hauls and
     annual mean ± 95 % CI); depth (scaled depth distribution of all vs positive hauls; density
     vs depth including zeros on a pseudo-log axis); season and gear.
   - *Length-based data*: length–weight fit with `ggFishPlots::plot_lw(outlier.sd =
     LW_OUTLIER_SD)` showing removed records; raised length distributions by cruise series;
     annual median and 10–90 % length; source of the length share and annual share above the
     threshold; *Data checks* (`data_checks()`: mean fish weight vs length-based prediction,
     length coverage of the catch, fishable ≤ total, density = catch / swept area, tow speed,
     positive hauls outside the prediction region, years without positives; flagged hauls to
     `ai/review/<stock>-flagged-hauls.csv`).
4. **Results and recommendations**, software, AI statement, references, script appendix.

## `docs/background/stock-background.qmd`

One background document per project (all stocks): purpose, current assessment and advice,
management, other stocks of the species, implications for the indices, and a *Fishable length*
section showing how the fishable-length threshold (`OVER_CM`) was derived: commercial length records
(`FISHABLE_GEAR`, reference fleet; confidential, read at render time and never saved),
`fishable_length_threshold()` in `R/fishable_length.R` (length where the 5-cm running mean of
the length frequency first reaches half of its mode), stability by period, and the commercial
versus survey length distributions. The section states whether the result equals `OVER_CM`. Do not make a separate
fishable-length document.

## `<stock>-1-summary.qmd`

1. **Abstract** (unnumbered, ≤ 300 words): whole routine and results. Placeholder until the
   index is final.
2. **Introduction**
   - *Purpose*: the same first two sentences as the survey-selection Purpose.
   - *Documents*: table of the documents with content and status.
   - *Use of generative AI*: exact models and roles; author responsibility.
3. **Data**: central table(s) from the data documents (hauls by cruise series).
4. **Model**, 5. **Indices**: placeholders until Steps 3–4, then the main figures and tables
   from those documents.
6. References.

## `<stock>-2-survey-selection.qmd`

Setup chunks first (`root.dir` in its own chunk, then config/source), then:

1. **Purpose** — two sentences: what is selected for which stock and why (`PURPOSE` in
   `config.yaml`); then the output and downstream use.
2. **Data** — database update and extraction dates (cite BioticExplorerServer); the current year is
   excluded until its surveys are complete (`LAST_YEAR`), then
   - *Stock area*: text, then **one overview map**: the stock area (combined ICES subareas from
     `STOCK_SUBAREAS`, or the `REGION_FILE` polygon) with all quality-filtered positive
     bottom-trawl hauls of the species in the region given by `MAP_LIMITS`, coloured
     inside/outside. No absences, no prediction region (that belongs to the fit document).
   - *Haul filter*: a table of every criterion with retained values and their meaning
     (decode quality codes from BAIT `quality-codes.md`), then the filter expression as a
     non-evaluated listing, then the stock-specific exceptions (e.g. CoastalS quality 2),
     Russian data, and the removal counts. Subsection *Tow distance and unspecified gear*:
     distance histogram (all vs positive hauls, limits marked), catch and catch per nmi by
     distance bin, positives removed by the unspecified-gear rule, and the decision whether the
     generic 0.3–5 nmi limits fit the species.
   - *Surveys and cruise series*: the encountered-on-a-cruise rule, the cruise-series table, and
     the list of surveys grouped as `Other` with the short cruise-series name and code
     (`survey_short_names` in `R/compile_functions.R`; uncoded surveys named through
     `SURVEY_NAMES` in `config.yaml`, via `survey_label()`).
   - Month columns use ranges (`format_months()`: "1–3", "2–6, 8–12").
   - *Dataset overview*: one metric/value table including number of years and true-zero
     hauls with the zero fraction in parentheses.
3. **Analysis** — *Survey catch and effort* (overview bars, annual bars), *Survey positions*
   (facet map with true zeros, grey land without bathymetry), *Gear* (box plot by gear + hauls by year and gear type; gear
   table with mean [min–max]), *Survey timing* (`plot_survey_timing()`: static figure, newest year on top, one label per
   year, cruise series dodged within a year, transparent segments; `interactive = TRUE` gives
   a plotly widget for data documents, but it adds about 3.8 MB and its container height
   still needs work in Quarto), *Gross-error screening* (table), *Other data in
   the database* (counts by mission type and gear; no positions).
4. **Results and recommendations** — *Ready for downstream use*, *Provisional*, *To decide*.
5. **Software and reproducibility**, AI statement, References, script appendix.

## Writing and figure rules

- **Text first.** The paragraph that refers to a figure or table comes before it.
- Every data-derived number is inline R; interpretive sentences that depend on the data (which
  series dominate, which gear) are computed, not typed, so the document stays true for another
  species or year.
- **Fixed colours** from `R/plot_helpers.R`: `cruise_series_colours()` (Okabe–Ito, same colour
  for a cruise series in every figure and stock) and `gear_colours()`. Order cruise series by
  first year with `order_cruise_series()`, `Other` last.
- Overview maps: `ggOceanMaps::basemap(limits = MAP_LIMITS, bathy.style = "rcb", bathy.alpha =
  0.35, land.col = "grey85")`, stock area as a translucent blue polygon densified in lon/lat
  before projection (`densify_lonlat()`, so parallels such as 62°N stay curved),
  `reorder_layers()` so land covers the polygon; points as filled circles with a thin black
  border (inside orange, outside light blue).
- Maps have no empty space above or below: compute the height with `map_fig_height()` from
  the bare `basemap()` (before `geom_sf()`, which resets the limits) and pass it as the knitr
  option `fig.height = <variable>` in the chunk header (a Quarto `fig-height: !expr` does not
  work here).
- Log axes use plain number labels (`scales::label_number()`), not `1e+02`.
- Render with a UTF-8 locale (`render.sh` sets it); GDAL cannot open the decomposed-Unicode
  project paths of macOS OneDrive folders otherwise.
- `fig-cap: !expr` captions must be single-quoted YAML strings without apostrophes.
- Shared code lives in `R/compile_functions.R` and `R/plot_helpers.R`; the documents call
  functions and show them in the appendix rather than repeating code.
