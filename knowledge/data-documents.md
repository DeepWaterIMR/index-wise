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
2. **Data** — database update and extraction dates (cite BioticExplorerServer), then
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
