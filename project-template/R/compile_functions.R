# compile_functions.R — Step 1 data compilation (index-wise).
#
# Shared by docs/data-report/survey-selection/<species>-compile-data.qmd. Implements
# index-wise knowledge/data-filtering.md: standard haul filter, mission-level
# (encountered-on-a-cruise) qualification per species, true zeros, duplicate diagnostic,
# swept-area density, depth filling and the fishable-length biomass fraction.
# Requires the packages loaded by R/0_setup.R.

# Cruise-series codes to short labels. Override per project with CRUISE_SERIES_LABELS in config.yaml.
cruise_series_labels <- c(
  `1` = "Other", `2` = "BSS", `3` = "BSS", `2,4` = "BSS", `4` = "BSS", `5` = "WinterS",
  `6` = "EcoS", `7` = "Other", `8` = "IBTS", `9` = "IBTS", `10` = "IBTS", `11` = "IBTS",
  `13` = "Other", `15` = "ShrimpS", `16` = "EggaN", `17` = "Other", `19` = "Other",
  `19,7` = "Other", `23` = "CoastalS", `24` = "IBTS", `24,8` = "IBTS", `25` = "EggaS",
  `26` = "Other", `31` = "Other"
)

# Short names of individual cruise series, used to identify surveys grouped as Other
# (abbreviations from BAIT knowledge/cruise-series-nicknames where they exist).
survey_short_names <- c(
  `1` = "BlueWhitingS", `2` = "BSS-AugSep", `3` = "BSS-OctNov", `4` = "0-groupS",
  `5` = "WinterS", `6` = "EcoS", `7` = "CodS", `13` = "SandeelS", `15` = "ShrimpS",
  `16` = "EggaN", `17` = "NES", `19` = "HerringS", `23` = "CoastalS", `25` = "EggaS",
  `26` = "FjordS", `31` = "CapelinS"
)

#' Cruise-series labels: config.yaml CRUISE_SERIES_LABELS when set, else the defaults
series_labels <- function() {
  lab <- if (exists("cfg", inherits = TRUE)) cfg$CRUISE_SERIES_LABELS else NULL
  if (length(lab)) unlist(lab) else cruise_series_labels
}

#' Label cruise series and gear types
#'
#' @param x Data frame with `cruiseseriescode`, `gear` and `gearname`.
#' @return `x` with `cruiseseries` and `geartype` columns.
label_surveys <- function(x) {
  x |>
    dplyr::mutate(
      # The database stores a missing cruise-series code as the string "NA" in some rows
      cruiseseriescode = dplyr::na_if(.data$cruiseseriescode, "NA"),
      cruiseseries = dplyr::coalesce(
        unname(series_labels()[as.character(.data$cruiseseriescode)]), "Other"),
      series_short = unname(survey_short_names[as.character(.data$cruiseseriescode)]),
      geartype = dplyr::case_when(
        grepl("GOV", .data$gearname) ~ "GOV",
        grepl("^32", .data$gear) ~ "Shrimp",
        grepl("^31", .data$gear) ~ "Cod",
        TRUE ~ "Other"
      )
    )
}

#' Lazy standard haul filter for quantitative research bottom-trawl hauls
#'
#' The stock area is defined either by ICES subareas (`STOCK_SUBAREAS` in `config.yaml`,
#' tested on the `icesarea` code in the database) or, when that is empty, by the polygon in
#' `REGION_FILE` (a bounding-box test here and an exact polygon test in
#' [area_filter_local()] after collection).
#'
#' @param stnall Lazy `stnall` table.
#' @param cfg Project configuration list.
#' @param last_year Last year to include (numeric literal for DuckDB).
#' @param obsolete_gear_codes Unspecified trawl codes to drop.
#' @param area Apply the stock-area condition? `FALSE` for the overview map.
#' @return Lazy table; apply [apply_samplequality()] and [area_filter_local()] after
#'   collecting.
standard_haul_filter <- function(stnall, cfg, last_year,
                                 obsolete_gear_codes = c("3100", "3101", "3130"),
                                 area = TRUE) {
  first_year <- as.integer(cfg$FIRST_YEAR)
  out <- stnall |>
    dplyr::filter(
      gearcategory == "Bottom trawls",
      missiontypename %in% c("Forskningsfartøy", "Leiefartøy"),
      startyear >= first_year,
      startyear <= last_year,
      !is.na(distance), !is.na(latitudestart), !is.na(longitudestart),
      latitudestart > 0,
      gearcondition %in% c("1", "2"),
      is.na(stationtype) | stationtype %in% c("1", "3", "9", "13"),
      distance >= 0.3, distance <= 5,
      is.na(gear) | !gear %in% obsolete_gear_codes
    )
  if (area) area_filter_lazy(out, cfg) else out
}

#' Stock-area condition evaluated in the database
#'
#' @param lazy Lazy station table.
#' @param cfg Project configuration.
area_filter_lazy <- function(lazy, cfg) {
  if (length(cfg$STOCK_SUBAREAS)) {
    prefixes <- paste0("27.", unlist(cfg$STOCK_SUBAREAS), ".")
    cond <- paste0("(", paste0("icesarea LIKE '", prefixes, "%'", collapse = " OR "), ")")
    return(dplyr::filter(lazy, dplyr::sql(cond)))
  }
  bb <- sf::st_bbox(sf::st_transform(read_region(cfg), 4326))
  dplyr::filter(lazy,
                longitudestart >= !!unname(bb["xmin"]), longitudestart <= !!unname(bb["xmax"]),
                latitudestart >= !!unname(bb["ymin"]), latitudestart <= !!unname(bb["ymax"]))
}

#' Exact stock-area test after collection (polygon rule only)
#'
#' @param x Collected station rows with `longitudestart`, `latitudestart`.
#' @param cfg Project configuration.
#' @return Logical vector: inside the stock area.
in_stock_area <- function(x, cfg) {
  if (length(cfg$STOCK_SUBAREAS)) {
    prefixes <- paste0("27.", unlist(cfg$STOCK_SUBAREAS), ".")
    return(Reduce(`|`, lapply(prefixes, function(p) startsWith(dplyr::coalesce(x$icesarea, ""), p))))
  }
  pts <- sf::st_as_sf(x, coords = c("longitudestart", "latitudestart"), crs = 4326,
                      remove = FALSE)
  region <- sf::st_transform(read_region(cfg), 4326)
  lengths(sf::st_intersects(pts, region)) > 0
}

#' Read the stock-area polygon (polygon rule)
#'
#' @param cfg Project configuration with `REGION_FILE`, `REGION_LAYER` and optionally
#'   `ACQUISITION_REGION`.
read_region <- function(cfg) {
  layer <- cfg$ACQUISITION_REGION_LAYER %||% cfg$REGION_LAYER
  sf::st_read(here::here(cfg$REGION_FILE), layer = layer, quiet = TRUE)
}

#' Conditional sample-quality rule (CoastalS code 23 keeps 1–2, others 1)
apply_samplequality <- function(x) {
  dplyr::filter(x, dplyr::if_else(
    !is.na(.data$cruiseseriescode) & .data$cruiseseriescode == "23",
    .data$samplequality %in% c("1", "2"),
    .data$samplequality %in% "1"
  ))
}

# Station-level columns kept in the roster.
station_cols <- c(
  "missionid", "serialnumber", "missiontype", "missiontypename", "missionnumber", "platform",
  "platformname", "cruise", "startyear", "station", "cruiseseriescode", "nation", "gear",
  "gearname", "gearcondition", "samplequality", "stationtype", "stationstartdate",
  "stationstopdate", "latitudestart", "longitudestart", "latitudeend", "longitudeend",
  "bottomdepthstart", "bottomdepthstop", "bottomdepthmean", "fishingdepthmean", "distance",
  "vesselspeed", "trawldoorspread", "wingspread", "verticaltrawlopening", "wirelength",
  "icesarea"
)

#' Compile the station dataset for one species
#'
#' Builds the qualifying-mission set from positive target catches after the standard filter,
#' then keeps every valid haul of those missions with the target catch joined on (true
#' zeros).
#'
#' @param con DuckDB connection to the IMR Biotic database.
#' @param cfg Project configuration (species already merged).
#' @param last_year Last year to include.
#' @return List with `stations` (one row per haul), `diagnostics`, `other_data`.
compile_species_stations <- function(con, cfg, last_year) {
  stnall <- dplyr::tbl(con, "stnall")
  filter_sp <- cfg$FILTER_SP

  lazy <- standard_haul_filter(stnall, cfg, last_year)
  n_candidate <- dplyr::pull(dplyr::count(lazy), n)
  if (n_candidate > (cfg$MAX_COLLECT_ROWS %||% 2e6))
    stop(n_candidate, " candidate catchsample rows exceed MAX_COLLECT_ROWS.")

  rows <- lazy |>
    dplyr::select(dplyr::all_of(c(station_cols, "commonname", "catchsampleid",
                                  "catchpartnumber", "catchcategory", "catchweight",
                                  "catchcount", "lengthsampleweight",
                                  "lengthsamplecount"))) |>
    dplyr::collect() |>
    apply_samplequality() |>
    dplyr::filter(in_stock_area(dplyr::pick(dplyr::everything()), cfg)) |>
    dplyr::mutate(haul_id = paste(missionid, serialnumber, sep = "_"))

  # Roster of all valid hauls, independent of the target catch.
  roster <- rows |>
    dplyr::select(dplyr::all_of(c("haul_id", station_cols))) |>
    dplyr::distinct(haul_id, .keep_all = TRUE)

  # Target catch per haul (sum of additive catchsamples).
  sp_rows <- dplyr::filter(rows, commonname %in% filter_sp)
  multi_sample <- sp_rows |>
    dplyr::count(haul_id, name = "n_catchsamples") |>
    dplyr::filter(n_catchsamples > 1)
  sp_catch <- sp_rows |>
    dplyr::group_by(haul_id) |>
    dplyr::summarise(
      biomass = sum(catchweight, na.rm = TRUE),
      count = sum(catchcount, na.rm = TRUE),
      lengthsampleweight = sum(lengthsampleweight, na.rm = TRUE),
      lengthsamplecount = sum(lengthsamplecount, na.rm = TRUE),
      weight_missing = any(is.na(catchweight)),
      .groups = "drop"
    )

  # Duplicate / inconsistency diagnostic.
  dupes <- dplyr::filter(sp_catch, count < lengthsamplecount | biomass < lengthsampleweight)
  # Incomplete records: target recorded but no weight.
  incomplete <- dplyr::filter(sp_catch, weight_missing & biomass == 0)

  # Mission-level qualification (encountered-on-a-cruise).
  positive <- dplyr::filter(sp_catch, biomass > 0 | count > 0,
                            !haul_id %in% c(dupes$haul_id, incomplete$haul_id))
  qualifying_missions <- unique(roster$missionid[roster$haul_id %in% positive$haul_id])

  stations <- roster |>
    dplyr::filter(missionid %in% qualifying_missions,
                  !haul_id %in% c(dupes$haul_id, incomplete$haul_id)) |>
    dplyr::left_join(dplyr::select(sp_catch, haul_id, biomass, count), by = "haul_id") |>
    dplyr::mutate(biomass = dplyr::coalesce(biomass, 0), count = dplyr::coalesce(count, 0)) |>
    label_surveys()

  if (!isTRUE(cfg$INCLUDE_RUSSIAN))
    stations <- dplyr::filter(stations, !nation %in% c("140", "90"))

  excluded <- dplyr::bind_rows(lapply(cfg$EXCLUDE_CRUISES %||% list(), tibble::as_tibble))
  if (nrow(excluded) > 0)
    stations <- dplyr::filter(
      stations, !paste(platformname, cruise) %in% paste(excluded$platformname, excluded$cruise))

  list(
    stations = stations,
    roster = dplyr::select(roster, haul_id, missionid, startyear, cruiseseriescode,
                           latitudestart, longitudestart),
    diagnostics = list(
      n_candidate_rows = n_candidate,
      n_valid_hauls = nrow(roster),
      n_qualifying_missions = length(qualifying_missions),
      duplicates = dupes,
      incomplete = incomplete,
      multi_sample = multi_sample
    )
  )
}

#' Swept area, density, dates and depth
#'
#' @param stations Output `stations` from [compile_species_stations()].
#' @param cfg Project configuration.
#' @return Stations with `swept_area` (nmi²), `rho_biomass` (kg nmi⁻²), `rho_abundance`
#'   (n nmi⁻²), `year`, `month`, `depth` and depth diagnostics.
add_response_and_covariates <- function(stations, cfg) {
  out <- stations |>
    dplyr::mutate(
      gear_width = as.numeric(cfg$GEAR_WIDTH),
      swept_area = distance * (gear_width / 1852),
      rho_biomass = biomass / swept_area,
      rho_abundance = count / swept_area,
      start_time = as.POSIXct(stationstartdate, tz = "UTC"),
      station_date = as.Date(start_time),
      duration_min = as.numeric(difftime(as.POSIXct(stationstopdate, tz = "UTC"),
                                         start_time, units = "mins")),
      year = as.integer(startyear),
      month = as.integer(format(start_time, "%m")),
      yday = as.integer(format(start_time, "%j")),
      depth_recorded = dplyr::coalesce(bottomdepthmean, bottomdepthstart, bottomdepthstop)
    )
  gebco <- ggOceanMaps::get_depth(
    data.frame(lon = out$longitudestart, lat = out$latitudestart),
    bathy.style = "rcb", bind = FALSE
  )
  out |>
    dplyr::mutate(
      depth_gebco = as.numeric(gebco),
      depth_source = dplyr::if_else(is.na(depth_recorded) | depth_recorded <= 0,
                                    "GEBCO", "recorded"),
      depth = dplyr::if_else(depth_source == "GEBCO", depth_gebco, depth_recorded),
      depth_ratio = depth_recorded / depth_gebco
    )
}

#' Individual length records of the target species for retained hauls
#'
#' @param con DuckDB connection.
#' @param cfg Project configuration.
#' @param stations Retained stations (`missionid`, `haul_id`).
#' @return Tibble with haul_id, length (cm), weight (kg), sex, raising factor.
collect_lengths <- function(con, cfg, stations) {
  missions <- unique(stations$missionid)
  haul_ids <- stations$haul_id
  dplyr::tbl(con, "indall") |>
    dplyr::filter(commonname %in% !!cfg$FILTER_SP, missionid %in% !!missions,
                  !is.na(length)) |>
    dplyr::select(missionid, serialnumber, catchsampleid, catchcount, lengthsamplecount,
                  length, individualweight, sex, maturationstage) |>
    dplyr::collect() |>
    dplyr::mutate(haul_id = paste(missionid, serialnumber, sep = "_")) |>
    dplyr::filter(haul_id %in% haul_ids) |>
    dplyr::mutate(
      length_cm = length * 100,
      weight_kg = individualweight,
      raising = dplyr::if_else(!is.na(catchcount) & !is.na(lengthsamplecount) &
                                 lengthsamplecount > 0, catchcount / lengthsamplecount, 1)
    )
}

#' Fit a log-log length–weight relationship with outlier screening
#'
#' Observations with absolute studentised residual > 4 are flagged as gross errors and
#' excluded from the final fit.
#'
#' @param lengths Output of [collect_lengths()].
#' @return List with `a`, `b` (weight in kg, length in cm), `fit`, `outliers`.
fit_length_weight <- function(lengths) {
  d <- dplyr::filter(lengths, !is.na(weight_kg), weight_kg > 0, length_cm > 0)
  fit0 <- stats::lm(log(weight_kg) ~ log(length_cm), data = d)
  out <- abs(stats::rstandard(fit0)) > 4
  fit <- stats::lm(log(weight_kg) ~ log(length_cm), data = d[!out, ])
  list(a = exp(unname(stats::coef(fit)[1])), b = unname(stats::coef(fit)[2]),
       fit = fit, n = sum(!out), outliers = d[out, ])
}

#' Fishable biomass fraction per haul
#'
#' Weight fraction of the catch at or above `over_cm`, from the raised length distribution
#' and the length–weight relationship. Positive hauls without length measurements get the
#' biomass-weighted mean fraction of their survey (mission), then of their cruise series and
#' year, then of the cruise series; `fishable_imputed` records which.
#'
#' @param stations Station data with `biomass`.
#' @param lengths Length records (gross errors removed).
#' @param lw Length–weight fit from [fit_length_weight()].
#' @param over_cm Threshold length (cm).
#' @return `stations` with `fishable_fraction`, `fishable_imputed`, `biomass_fishable`,
#'   `rho_biomass_fishable`.
add_fishable_biomass <- function(stations, lengths, lw, over_cm) {
  frac <- lengths |>
    dplyr::mutate(w = raising * lw$a * length_cm^lw$b) |>
    dplyr::group_by(haul_id) |>
    dplyr::summarise(fishable_fraction = sum(w[length_cm >= over_cm]) / sum(w),
                     n_measured = dplyr::n(), .groups = "drop")

  out <- stations |>
    dplyr::left_join(frac, by = "haul_id") |>
    dplyr::mutate(n_measured = dplyr::coalesce(n_measured, 0L))

  wmean <- function(f, w) if (all(is.na(f))) NA_real_ else stats::weighted.mean(f, w, na.rm = TRUE)
  by_mission <- out |> dplyr::filter(!is.na(fishable_fraction)) |>
    dplyr::group_by(missionid) |>
    dplyr::summarise(f_mission = wmean(fishable_fraction, biomass), .groups = "drop")
  by_cs_year <- out |> dplyr::filter(!is.na(fishable_fraction)) |>
    dplyr::group_by(cruiseseries, year) |>
    dplyr::summarise(f_cs_year = wmean(fishable_fraction, biomass), .groups = "drop")
  by_cs <- out |> dplyr::filter(!is.na(fishable_fraction)) |>
    dplyr::group_by(cruiseseries) |>
    dplyr::summarise(f_cs = wmean(fishable_fraction, biomass), .groups = "drop")

  out |>
    dplyr::left_join(by_mission, by = "missionid") |>
    dplyr::left_join(by_cs_year, by = c("cruiseseries", "year")) |>
    dplyr::left_join(by_cs, by = "cruiseseries") |>
    dplyr::mutate(
      fishable_imputed = dplyr::case_when(
        biomass == 0 ~ "zero catch",
        !is.na(fishable_fraction) ~ "measured",
        !is.na(f_mission) ~ "survey mean",
        !is.na(f_cs_year) ~ "series-year mean",
        !is.na(f_cs) ~ "series mean",
        TRUE ~ "none"
      ),
      fishable_fraction = dplyr::case_when(
        biomass == 0 ~ 0,
        !is.na(fishable_fraction) ~ fishable_fraction,
        TRUE ~ dplyr::coalesce(f_mission, f_cs_year, f_cs)
      ),
      biomass_fishable = biomass * fishable_fraction,
      rho_biomass_fishable = biomass_fishable / swept_area
    ) |>
    dplyr::select(-f_mission, -f_cs_year, -f_cs)
}

#' Counts of other data types for the species in the stock area (no positions)
#'
#' @param con DuckDB connection.
#' @param cfg Project configuration.
#' @return Tibble of station counts by mission type and gear category.
other_data_summary <- function(con, cfg) {
  dplyr::tbl(con, "stnall") |>
    dplyr::filter(commonname %in% !!cfg$FILTER_SP) |>
    area_filter_lazy(cfg) |>
    dplyr::distinct(missionid, serialnumber, missiontypename, gearcategory, startyear,
                    icesarea, longitudestart, latitudestart) |>
    dplyr::collect() |>
    dplyr::filter(in_stock_area(dplyr::pick(dplyr::everything()), cfg)) |>
    dplyr::group_by(missiontypename, gearcategory) |>
    dplyr::summarise(stations = dplyr::n(), first_year = min(startyear, na.rm = TRUE),
                     last_year = max(startyear, na.rm = TRUE), .groups = "drop") |>
    dplyr::arrange(dplyr::desc(stations))
}

#' Prediction region: survey coverage of ICES subareas 1 and 2
#'
#' Concave hull of all valid research bottom-trawl hauls in the stock area (species
#' independent, so species in one project can share the region), optionally cut at a
#' southern latitude (e.g. 62°N, the southern boundary of ICES Subarea 2).
#'
#' @param roster Valid-haul roster with `longitudestart`, `latitudestart`.
#' @param crs Projected CRS (EPSG).
#' @param ratio Concavity ratio for [sf::st_concave_hull()].
#' @param label Region name (`REGION` in `config.yaml`).
#' @return sf polygon with a `region` column.
build_prediction_region <- function(roster, crs, ratio = 0.05, label = "ALL",
                                    min_lat = NULL) {
  hull <- sf::st_as_sf(roster, coords = c("longitudestart", "latitudestart"), crs = 4326) |>
    sf::st_transform(crs) |>
    sf::st_union() |>
    sf::st_concave_hull(ratio = ratio) |>
    sf::st_buffer(5000)
  if (!is.null(min_lat)) {
    # Densified lon/lat box north of min_lat (dense vertices keep the edge on the parallel
    # after projection; avoids an lwgeom dependency).
    lon <- seq(-60, 100, by = 0.25)
    lat <- seq(min_lat, 89, by = 0.25)
    box <- rbind(cbind(lon, min_lat), cbind(100, lat), cbind(rev(lon), 89), cbind(-60, rev(lat)))
    north <- sf::st_transform(sf::st_sfc(sf::st_polygon(list(box)), crs = 4326), crs)
    hull <- sf::st_intersection(hull, north)
  }
  sf::st_sf(region = label, geometry = sf::st_make_valid(hull))
}

#' Quality-filtered positive bottom-trawl hauls without the area filter
#'
#' Used for the overview map that shows which observations fall inside and outside the
#' stock area. Applies the standard haul filter except the stock-area condition, within
#' `MAP_LIMITS`.
#'
#' @param con DuckDB connection.
#' @param cfg Project configuration (species merged).
#' @param last_year Last year to include.
#' @return Tibble of positive hauls with `inside` (in the stock area).
collect_positive_observations <- function(con, cfg, last_year) {
  lim <- unlist(cfg$MAP_LIMITS)
  dplyr::tbl(con, "stnall") |>
    dplyr::filter(commonname %in% !!cfg$FILTER_SP, catchweight > 0 | catchcount > 0) |>
    standard_haul_filter(cfg, last_year, area = FALSE) |>
    dplyr::filter(longitudestart >= !!lim[1], longitudestart <= !!lim[2],
                  latitudestart >= !!lim[3], latitudestart <= !!lim[4]) |>
    dplyr::distinct(missionid, serialnumber, cruiseseriescode, samplequality, startyear,
                    icesarea, longitudestart, latitudestart) |>
    dplyr::collect() |>
    apply_samplequality() |>
    dplyr::mutate(inside = in_stock_area(dplyr::pick(dplyr::everything()), cfg))
}

#' Reference-code descriptions for the quality fields
#'
#' @param con DuckDB connection.
#' @return Tibble of codeindex rows for gearcondition, samplequality and stationtype.
quality_code_table <- function(con) {
  dplyr::tbl(con, "codeindex") |>
    dplyr::filter(reftable %in% c("gearcondition", "samplequality", "stationtype")) |>
    dplyr::select(reftable, code, shortname, description) |>
    dplyr::collect()
}

#' Tow-distance diagnostics: all valid hauls and target-positive hauls before the distance
#' and unspecified-gear filters
#'
#' @param con DuckDB connection.
#' @param cfg Project configuration (species merged).
#' @param last_year Last year to include.
#' @return Tibble, one row per haul: distance, gear, cruiseseriescode, target catch (kg).
distance_diagnostics <- function(con, cfg, last_year) {
  first_year <- as.integer(cfg$FIRST_YEAR)
  base <- dplyr::tbl(con, "stnall") |>
    dplyr::filter(
      gearcategory == "Bottom trawls",
      missiontypename %in% c("Forskningsfartøy", "Leiefartøy"),
      startyear >= first_year, startyear <= last_year,
      gearcondition %in% c("1", "2"),
      is.na(stationtype) | stationtype %in% c("1", "3", "9", "13")
    ) |>
    area_filter_lazy(cfg)
  hauls <- base |>
    dplyr::distinct(missionid, serialnumber, cruiseseriescode, samplequality, gear,
                    distance, icesarea, longitudestart, latitudestart) |>
    dplyr::collect() |>
    apply_samplequality() |>
    dplyr::filter(in_stock_area(dplyr::pick(dplyr::everything()), cfg)) |>
    dplyr::distinct(missionid, serialnumber, .keep_all = TRUE)
  catch <- base |>
    dplyr::filter(commonname %in% !!cfg$FILTER_SP) |>
    dplyr::group_by(missionid, serialnumber) |>
    dplyr::summarise(catch_kg = sum(catchweight, na.rm = TRUE), .groups = "drop") |>
    dplyr::collect()
  hauls |>
    dplyr::left_join(catch, by = c("missionid", "serialnumber")) |>
    dplyr::mutate(catch_kg = dplyr::coalesce(catch_kg, 0)) |>
    dplyr::select(cruiseseriescode, gear, distance, catch_kg)
}

#' Survey label for the Other-survey table
#'
#' Short cruise-series name and code when the survey has a code; otherwise the survey name
#' from `SURVEY_NAMES` in `config.yaml` (keyed by cruise number); otherwise "–".
#'
#' @param code Cruise-series code.
#' @param short Short cruise-series name (`series_short`).
#' @param cruise Cruise number.
#' @param cfg Project configuration.
survey_label <- function(code, short, cruise, cfg) {
  code <- dplyr::na_if(as.character(code), "NA")
  named <- unlist(cfg$SURVEY_NAMES)
  by_cruise <- if (length(named)) unname(named[as.character(cruise)]) else NA_character_
  dplyr::case_when(
    !is.na(code) ~ paste0(dplyr::coalesce(short, "?"), " (", code, ")"),
    !is.na(by_cruise) ~ by_cruise,
    TRUE ~ "–"
  )
}
