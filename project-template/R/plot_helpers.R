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

#' ICES statistical areas used to assign `icesarea` in the Biotic database
#'
#' `ICES_AREAS_FILE: null` (default) returns `BioticExplorerServer::icesAreas`, the polygons
#' that coded the `icesarea` column, so that the area-code filter and any polygon operation
#' agree. A file is read only when one is configured. Do not substitute another release:
#' the ICES GIS 2021-11-01 release draws the 4.a/2.a boundary diagonally from 3.5° W, 63° N
#' to the Norwegian coast instead of along 62° N (Regulation (EC) No 218/2009, Annex III).
#'
#' @param cfg Project configuration with `ICES_AREAS_FILE`.
#' @return sf polygons (EPSG:4326) with `Major_FA`, `SubArea`, `Area_Full`.
read_ices_areas <- function(cfg) {
  if (is.null(cfg$ICES_AREAS_FILE)) {
    x <- BioticExplorerServer::icesAreas
    suppressWarnings(sf::st_crs(x) <- 4326)
    return(x)
  }
  sf::st_read(here::here(cfg$ICES_AREAS_FILE), quiet = TRUE)
}

#' Stock-area polygon: combined ICES subareas, or the REGION_FILE polygon
#'
#' Dissolves the stock subareas in a polar stereographic projection (a small positive and
#' negative buffer closes slivers between neighbouring divisions). For maps, the polygon is
#' cut at the northern map limit so that the pole does not distort the map; use
#' `cap = FALSE` for any data or region operation, or hauls north of the map limit are lost.
#' `ICES_AREAS_FILE` should hold the polygons the Biotic database used to assign `icesarea`
#' (BioticExplorerServer `icesAreas`), so that the area-code filter and the polygon agree.
#'
#' @param cfg Project configuration with `ICES_AREAS_FILE`, `STOCK_SUBAREAS`, `MAP_LIMITS`.
#' @param crs Projected CRS for dissolving (default Arctic polar stereographic).
#' @param cap Cut the polygon at the northern map limit (maps only).
#' @return sf polygon (EPSG:4326) with column `area`.
read_stock_area <- function(cfg, crs = 3995, cap = TRUE) {
  if (!length(cfg$STOCK_SUBAREAS)) {
    layer <- cfg$ACQUISITION_REGION_LAYER %||% cfg$REGION_LAYER
    return(sf::st_read(here::here(cfg$REGION_FILE), layer = layer, quiet = TRUE) |>
             sf::st_transform(4326) |>
             sf::st_union() |>
             sf::st_sf(area = cfg$REGION, geometry = _))
  }
  lim <- unlist(cfg$MAP_LIMITS)
  lon <- seq(-180, 180, by = 1)
  cap_poly <- sf::st_sfc(sf::st_polygon(list(rbind(
    cbind(lon, lim[3] - 10), cbind(rev(lon), lim[4]), c(-180, lim[3] - 10)
  ))), crs = 4326) |>
    sf::st_transform(crs)
  read_ices_areas(cfg) |>
    dplyr::filter(.data$Major_FA == "27", .data$SubArea %in% cfg$STOCK_SUBAREAS) |>
    densify_lonlat() |>
    sf::st_transform(crs) |>
    sf::st_make_valid() |>
    sf::st_union() |>
    sf::st_buffer(2000) |>
    sf::st_buffer(-2000) |>
    (\(x) if (cap) sf::st_intersection(x, cap_poly) else x)() |>
    sf::st_transform(4326) |>
    sf::st_sf(area = paste("ICES", paste(cfg$STOCK_SUBAREAS, collapse = " and ")), geometry = _)
}

#' Compact ranges of consecutive integers (months, years)
#'
#' @param x Integers, possibly repeated and unsorted.
#' @param last_and Join the last range with "and" (for prose) rather than a comma.
#' @return One string, e.g. "1995–1996, 1998–2002, 2005 and 2007–2008".
format_ranges <- function(x, last_and = TRUE) {
  x <- sort(unique(stats::na.omit(as.integer(x))))
  if (!length(x)) return("")
  runs <- split(x, cumsum(c(1, diff(x) != 1)))
  parts <- vapply(runs, function(r) {
    if (length(r) == 1) as.character(r) else paste0(r[1], "–", r[length(r)])
  }, character(1), USE.NAMES = FALSE)
  if (!last_and || length(parts) < 2) return(paste(parts, collapse = ", "))
  paste(paste(parts[-length(parts)], collapse = ", "), "and", parts[length(parts)])
}

#' Compact month ranges, e.g. "1–3, 8–12"
#'
#' @param m Integer months (1–12), possibly repeated.
#' @return One string.
format_months <- function(m) format_ranges(m, last_and = FALSE)

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
  if (is.null(lim$x) || is.null(lim$y)) {  # no stored limits: use the built panel ranges
    pp <- ggplot2::ggplot_build(p)$layout$panel_params[[1]]
    lim <- list(x = pp$x_range, y = pp$y_range)
  }
  aspect <- diff(lim$y) / diff(lim$x)
  round(nrow * ((width - side) / ncol) * aspect + extra, 2)
}

#' Prediction-grid map coloured by depth
#'
#' Wraps the `plot()` method of sdmTMBexperiments for prediction grids
#' (`plot.sdmTMB_prediction_grid()`: one square per cell, sized to the cell, turbo palette)
#' and adds the prediction-region outline, depth bins and the figure height.
#'
#' @param grid One year of the prediction grid (`X`, `Y` in km, `depth` in m), as built by
#'   [sdmTMBexperiments::make_prediction_grid()].
#' @param crs Projected CRS of `X` and `Y` (EPSG code); used when `grid` lacks its `crs`
#'   attribute.
#' @param cell_km Grid-cell size (km), used for the symbol size.
#' @param region Optional prediction-region polygon (sf) drawn as an outline.
#' @param step Depth-bin width (m).
#' @return A list with the map (`plot`) and its figure height in inches (`height`).
plot_grid_depth <- function(grid, crs, cell_km, region = NULL, step = 100) {
  if (!inherits(grid, "sdmTMB_prediction_grid")) {
    class(grid) <- c("sdmTMB_prediction_grid", class(grid))
  }
  p <- plot(grid, value = "depth", crs = attr(grid, "crs") %||% crs, coord_multiplier = 1000,
            point_size = 0.11 * cell_km, base_size = 8)
  height <- map_fig_height(p, extra = 0.9)
  breaks <- seq(floor(min(grid$depth, na.rm = TRUE) / step) * step,
                ceiling(max(grid$depth, na.rm = TRUE) / step) * step, by = step)
  if (!is.null(region)) {
    p <- p + ggplot2::geom_sf(data = region, fill = NA, colour = "black", linewidth = 0.4,
                              inherit.aes = FALSE)
  }
  p <- suppressMessages(p +  # replaces the method's continuous colour scale
    ggplot2::scale_colour_viridis_b(option = "turbo", breaks = breaks,
                                    limits = range(breaks), show.limits = TRUE,
                                    labels = function(x) ifelse(length(breaks) > 11 & x %% (2 * step) != 0, "", x),
                                    name = "Depth (m)") +
    ggplot2::theme(axis.title = ggplot2::element_blank(),
                   legend.key.width = ggplot2::unit(1.6, "cm")))
  list(plot = ggOceanMaps::reorder_layers(p), height = height)
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

#' Annual station maps of biomass density
#'
#' One panel per year with all retained hauls: zero hauls as dark crosses, positive hauls as
#' semi-transparent circles with size and colour binned by quantiles of the positive densities,
#' common to all years; the largest circles are drawn first so that smaller ones stay visible
#' (after ref-assessment-index `bubble_map()`, Figure 1.18 of Compile_all_data). Shows how the
#' survey coverage and the positive hauls change between years. Use a pale land colour in
#' `base` so that the zero crosses stand out.
#'
#' @param x Station data with `year`, `longitudestart`, `latitudestart` and `density`.
#' @param base A `ggOceanMaps::basemap()` covering the data (build it once and reuse).
#' @param ncol Facet columns.
#' @param label Legend title.
#' @param probs Quantiles of the positive densities used as bin breaks.
#' @param alpha Transparency of the circles.
#' @param size_range Circle size range.
#' @return ggplot.
plot_annual_density <- function(x, base, ncol = 6, label = "Density (kg/nmi²)",
                                probs = c(0.25, 0.5, 0.75, 0.9, 0.99), alpha = 0.5,
                                size_range = c(0.4, 4)) {
  x <- dplyr::filter(x, !is.na(density))
  pos <- dplyr::filter(x, density > 0)
  # Quantile bins of the positive densities, common to all years (after the redfish
  # bubble_map() in ref-assessment-index/R/bubble_map.R)
  breaks <- unique(signif(stats::quantile(pos$density, probs, names = FALSE), 2))
  limits <- c(0, max(pos$density) * 1.001)
  cols <- viridis::turbo(length(breaks) + 1, begin = 0.12, end = 0.95)
  base +
    ggspatial::geom_spatial_point(
      data = dplyr::filter(x, density == 0),
      ggplot2::aes(longitudestart, latitudestart), shape = 3, size = 0.3, stroke = 0.25,
      colour = "grey15", alpha = 0.5, crs = 4326) +
    ggspatial::geom_spatial_point(
      data = dplyr::arrange(pos, dplyr::desc(density)),
      ggplot2::aes(longitudestart, latitudestart, size = density, fill = density),
      shape = 21, stroke = 0.15, colour = "grey20", alpha = alpha, crs = 4326) +
    ggplot2::binned_scale(
      aesthetics = "fill", palette = function(n) cols, breaks = breaks, limits = limits,
      labels = scales::label_number(drop0trailing = TRUE, big.mark = " "),
      name = label, guide = "legend") +
    ggplot2::scale_size_binned(
      breaks = breaks, limits = limits, range = size_range,
      labels = scales::label_number(drop0trailing = TRUE, big.mark = " "), name = label) +
    ggplot2::guides(fill = ggplot2::guide_legend(nrow = 1, override.aes = list(alpha = 0.8)),
                    size = ggplot2::guide_legend(nrow = 1)) +
    ggplot2::facet_wrap(~year, ncol = ncol) +
    ggplot2::theme(axis.title = ggplot2::element_blank(),
                   axis.text = ggplot2::element_blank(),
                   axis.ticks = ggplot2::element_blank(),
                   strip.text = ggplot2::element_text(size = 7,
                                                      margin = ggplot2::margin(1, 0, 1, 0)),
                   panel.spacing = ggplot2::unit(0.05, "lines"),
                   legend.position = "bottom")
}
