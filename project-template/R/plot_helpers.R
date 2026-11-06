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

#' Compact month ranges
#'
#' @param m Integer months (1–12), possibly repeated.
#' @return One string, e.g. "1–3, 8–12" for months 1, 2, 3, 8, 9, 10, 11, 12.
format_months <- function(m) {
  m <- sort(unique(stats::na.omit(as.integer(m))))
  if (!length(m)) return("")
  runs <- split(m, cumsum(c(1, diff(m) != 1)))
  paste(vapply(runs, function(r) {
    if (length(r) == 1) as.character(r) else paste0(r[1], "–", r[length(r)])
  }, character(1)), collapse = ", ")
}

#' Height (inches) of a ggOceanMaps map so the HTML figure has no empty space
#'
#' Uses the projected limits stored in the map's `coord_sf()`.
#'
#' @param p A `ggOceanMaps::basemap()` plot.
#' @param width Figure width (inches).
#' @param ncol,nrow Facet columns and rows (1 for a single map).
#' @param extra Height of legend, strips and margins that do not scale with the map (inches).
#' @param side Width taken by axis labels and margins (inches).
map_fig_height <- function(p, width = 6.69, ncol = 1, nrow = 1, extra = 0.6, side = 0.6) {
  lim <- p$coordinates$limits
  aspect <- diff(lim$y) / diff(lim$x)
  round(nrow * ((width - side) / ncol) * aspect + extra, 2)
}

#' Standard survey-timing figure
#'
#' One segment per survey from its first to last retained haul (day of year), newest year at
#' the top, one axis label per year. Cruise series are dodged slightly within a year so that
#' simultaneous surveys remain visible. With `interactive = TRUE` the figure is returned as a
#' plotly widget with survey details in the tooltip (about 3.8 MB added to a self-contained
#' HTML; the container height still needs work in Quarto, see ref-assessment-index
#' docs/data/Compile_all_data.Rmd for a working R Markdown setup).
#'
#' @param dt Station data with `year`, `yday`, `missionid`, `cruiseseries`, `platformname`,
#'   `cruise`, `geartype`.
#' @param colours Named colours for the cruise series.
#' @param interactive Return a plotly widget?
#' @param height Figure height in inches (used for the plotly widget).
#' @return ggplot or plotly object.
plot_survey_timing <- function(dt, colours, interactive = FALSE, height = 8) {
  series <- levels(factor(dt$cruiseseries))
  k <- length(series)
  step <- if (k > 1) 0.7 / (k - 1) else 0
  timing <- dt |>
    dplyr::group_by(year, missionid, cruiseseries, platformname, cruise) |>
    dplyr::summarise(first = min(yday), last = max(yday),
                     gear = paste(sort(unique(geartype)), collapse = ", "),
                     hauls = dplyr::n(), .groups = "drop") |>
    dplyr::mutate(
      first = as.Date("2020-01-01") + first - 1,
      last = as.Date("2020-01-01") + last - 1,
      ypos = year + (match(as.character(cruiseseries), series) - (k + 1) / 2) * step,
      text = paste0(cruiseseries, " ", year, "<br>Vessel: ", platformname,
                    "<br>Cruise: ", cruise, "<br>Gear: ", gear, "<br>Hauls: ", hauls,
                    "<br>", format(first, "%d %b"), " – ", format(last, "%d %b"))
    )
  p <- ggplot2::ggplot(timing, ggplot2::aes(x = first, xend = last, y = ypos, yend = ypos,
                                            colour = cruiseseries, text = text)) +
    ggplot2::geom_segment(linewidth = 1.4, alpha = 0.7) +
    ggplot2::scale_colour_manual(values = colours) +
    ggplot2::scale_x_date(date_labels = "%b", date_breaks = "1 month",
                          limits = as.Date(c("2020-01-01", "2020-12-31")),
                          expand = ggplot2::expansion(mult = 0.01)) +
    ggplot2::scale_y_continuous(breaks = seq(min(timing$year), max(timing$year), 1),
                                expand = ggplot2::expansion(add = 0.6)) +
    ggplot2::labs(x = "Month", y = "Year", colour = "Cruise series") +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(size = 7))
  if (interactive && requireNamespace("plotly", quietly = TRUE)) {
    # The widget container must have the same height as the plotly layout; otherwise
    # knitr's default container height crops the figure and the plot covers the caption.
    w <- plotly::ggplotly(p, tooltip = "text", height = round(height * 96))
    w$height <- round(height * 96)
    w$sizingPolicy$knitr$figure <- TRUE
    w
  } else p
}
