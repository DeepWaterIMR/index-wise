# fishable_length.R — fishable-length threshold from commercial length distributions.
#
# The threshold is the length at which the smoothed length-frequency distribution of the
# commercial catch first reaches half of its modal frequency on the ascending limb: an
# approximation of the length at 50 % retention by the fishery (selectivity times
# availability). Reference-fleet data are confidential: read them on the laptop at render
# time and never save the records.

#' Length records of the species from commercial (reference-fleet) catches
#'
#' @param con DuckDB connection to the IMR Biotic database.
#' @param cfg Project configuration (species merged).
#' @param gear_category Biotic gear category of the commercial fishery (e.g. "Hooks").
#' @param mission_prefix Start of the mission-type name (default reference fleet).
#' @param first_year,last_year Year range.
#' @return Tibble with `year` and `length_cm`.
collect_commercial_lengths <- function(con, cfg, gear_category = "Hooks",
                                       mission_prefix = "Refera", first_year = 2000,
                                       last_year = as.integer(format(Sys.Date(), "%Y")) - 1L) {
  dplyr::tbl(con, "indall") |>
    dplyr::filter(commonname %in% !!cfg$FILTER_SP, gearcategory == !!gear_category,
                  substr(missiontypename, 1, 6) == !!mission_prefix,
                  startyear >= !!first_year, startyear <= !!last_year, !is.na(length)) |>
    area_filter_lazy(cfg) |>
    dplyr::select(year = startyear, length, icesarea, longitudestart, latitudestart) |>
    dplyr::collect() |>
    dplyr::filter(in_stock_area(dplyr::pick(dplyr::everything()), cfg)) |>
    dplyr::transmute(year, length_cm = floor(length * 100))
}

#' Fishable-length threshold from a length distribution
#'
#' @param length_cm Lengths in cm (integer-floored).
#' @param window Width of the centred running mean (cm).
#' @param prop Proportion of the modal frequency defining the threshold (default 0.5).
#' @return List with `threshold`, `mode` and the frequency table `freq` (length, n, smooth).
fishable_length_threshold <- function(length_cm, window = 5, prop = 0.5) {
  freq <- tibble::tibble(length = length_cm) |>
    dplyr::count(length) |>
    tidyr::complete(length = seq(min(length), max(length)), fill = list(n = 0)) |>
    dplyr::arrange(length)
  freq$smooth <- as.numeric(stats::filter(freq$n, rep(1 / window, window), sides = 2))
  mode_len <- freq$length[which.max(freq$smooth)]
  peak <- max(freq$smooth, na.rm = TRUE)
  threshold <- freq$length[which(freq$length <= mode_len & freq$smooth >= prop * peak)[1]]
  list(threshold = threshold, mode = mode_len, freq = freq)
}
