# plot_helpers.R — shared colours and small plotting helpers for all documents.
# Fixed colour mappings keep cruise series and gear types the same colour in every figure
# and in both species. Colours follow the Okabe–Ito colour-blind-safe palette.

#' Fixed cruise-series colours
#'
#' @param levels Cruise-series labels present in the data.
#' @return Named character vector of colours.
cruise_series_colours <- function(levels = NULL) {
  pal <- c(
    WinterS = "#0072B2", EcoS = "#009E73", CoastalS = "#E69F00", EggaN = "#CC79A7",
    EggaS = "#882255", BSS = "#56B4E9", IBTS = "#D55E00", ShrimpS = "#F0E442",
    Other = "#7F7F7F"
  )
  if (is.null(levels)) return(pal)
  missing <- setdiff(levels, names(pal))
  if (length(missing)) pal <- c(pal, stats::setNames(rep("#333333", length(missing)), missing))
  pal[levels]
}

#' Add vertices along lon/lat polygon edges
#'
#' ICES boundaries follow parallels and meridians with few vertices; in a projected map a
#' parallel drawn between two distant vertices becomes a straight chord. Segmenting in degree
#' space (CRS temporarily removed, so no lwgeom is needed) keeps the edges on the parallels.
#'
#' @param x sf object in EPSG:4326.
#' @param max_deg Maximum segment length in degrees.
densify_lonlat <- function(x, max_deg = 0.1) {
  crs <- sf::st_crs(x)
  geom <- sf::st_geometry(x)
  sf::st_crs(geom) <- NA
  geom <- sf::st_segmentize(geom, dfMaxLength = max_deg)
  sf::st_crs(geom) <- crs
  sf::st_set_geometry(x, geom)
}

#' Fixed gear-type colours
gear_colours <- function() {
  c(Shrimp = "#0072B2", Cod = "#D55E00", GOV = "#009E73", Other = "#7F7F7F")
}

#' Order cruise series by first year of data, with Other last
#'
#' @param x Character vector of cruise series.
#' @param year Matching years.
order_cruise_series <- function(x, year) {
  first <- tapply(year, x, min)
  lev <- names(sort(first))
  factor(x, levels = c(setdiff(lev, "Other"), intersect("Other", lev)))
}

#' Stock-area polygon: combined ICES subareas, or the REGION_FILE polygon
#'
#' Dissolves the stock subareas in a polar stereographic projection (a small positive and
#' negative buffer closes slivers between neighbouring divisions) and cuts the polygon at
#' the northern map limit so that the pole does not distort the map.
#'
#' @param cfg Project configuration with `ICES_AREAS_FILE`, `STOCK_SUBAREAS`, `MAP_LIMITS`.
#' @param crs Projected CRS for dissolving (default Arctic polar stereographic).
#' @return sf polygon (EPSG:4326) with column `area`.
read_stock_area <- function(cfg, crs = 3995) {
  if (!length(cfg$STOCK_SUBAREAS)) {
    layer <- cfg$ACQUISITION_REGION_LAYER %||% cfg$REGION_LAYER
    return(sf::st_read(here::here(cfg$REGION_FILE), layer = layer, quiet = TRUE) |>
             sf::st_transform(4326) |>
             sf::st_union() |>
             sf::st_sf(area = cfg$REGION, geometry = _))
  }
  lim <- unlist(cfg$MAP_LIMITS)
  lon <- seq(-180, 180, by = 1)
  cap <- sf::st_sfc(sf::st_polygon(list(rbind(
    cbind(lon, lim[3] - 10), cbind(rev(lon), lim[4]), c(-180, lim[3] - 10)
  ))), crs = 4326) |>
    sf::st_transform(crs)
  sf::st_read(here::here(cfg$ICES_AREAS_FILE), quiet = TRUE) |>
    dplyr::filter(.data$Major_FA == "27", .data$SubArea %in% cfg$STOCK_SUBAREAS) |>
    densify_lonlat() |>
    sf::st_transform(crs) |>
    sf::st_make_valid() |>
    sf::st_union() |>
    sf::st_buffer(2000) |>
    sf::st_buffer(-2000) |>
    sf::st_intersection(cap) |>
    sf::st_transform(4326) |>
    sf::st_sf(area = paste("ICES", paste(cfg$STOCK_SUBAREAS, collapse = " and ")), geometry = _)
}
