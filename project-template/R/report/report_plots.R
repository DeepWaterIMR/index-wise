# Figures and tables of the report documents, drawn from the caches written by
# R/report/report_lib.R. Each function takes the list of post-processed products
# (`post`, one element per product, named by product).

product_colours <- function(labels) {
  stats::setNames(c("#0072B2", "#D55E00", "#009E73")[seq_along(labels)], labels)
}

#' Hauls per year by cruise series, with the share of hauls that caught the species
#'
#' @param dt Model data.
#' @param sp Species name for the axis label.
#' @return A two-panel ggplot (cowplot).
plot_report_stations <- function(dt, sp) {
  cols <- cruise_series_colours(sort(unique(as.character(dt$cruiseseries))))
  a <- ggplot2::ggplot(dt, ggplot2::aes(.data$year, fill = .data$cruiseseries)) +
    ggplot2::geom_bar(width = 0.85) +
    ggplot2::scale_fill_manual(values = cols, name = NULL) +
    ggplot2::labs(x = NULL, y = "Hauls") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom") +
    ggplot2::guides(fill = ggplot2::guide_legend(nrow = 1))
  share <- dt |>
    dplyr::group_by(.data$year) |>
    dplyr::summarise(total = mean(.data$value > 0), fishable = mean(.data$value_fishable > 0), .groups = "drop") |>
    tidyr::pivot_longer(c("total", "fishable"), names_to = "type", values_to = "share") |>
    dplyr::mutate(type = factor(.data$type, c("total", "fishable"), c(paste("All", tolower(sp)), paste("Fishable", tolower(sp)))))
  b <- ggplot2::ggplot(share, ggplot2::aes(.data$year, .data$share, colour = .data$type)) +
    ggplot2::geom_line() + ggplot2::geom_point(size = 0.8) +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, NA)) +
    ggplot2::scale_colour_manual(values = c("black", "#D55E00"), name = NULL) +
    ggplot2::labs(x = "Year", y = "Hauls with catch") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom")
  cowplot::plot_grid(a, b, ncol = 1, labels = "AUTO", rel_heights = c(1.15, 1), align = "v", axis = "lr")
}

#' Normal quantile-quantile plots of the randomised quantile residuals of every product
#'
#' @param post Post-processed products.
#' @param component_names Names of the delta components.
#' @return ggplot, products in rows and components in columns.
plot_report_qq <- function(post, component_names = c("Encounter", "Positive")) {
  d <- purrr::imap_dfr(post, function(p, label) {
    purrr::imap_dfr(p$resid, function(r, k) {
      r <- r[is.finite(r)]
      if (!length(r)) return(NULL)
      q <- stats::qqnorm(r, plot.it = FALSE)
      tibble::tibble(product = label, component = component_names[k], theoretical = q$x, sample = q$y)
    })
  })
  d$product <- factor(d$product, names(post))
  ggplot2::ggplot(d, ggplot2::aes(.data$theoretical, .data$sample)) +
    ggplot2::geom_abline(colour = "grey50", linetype = 2) +
    ggplot2::geom_point(size = 0.4, alpha = 0.4) +
    ggplot2::facet_grid(product ~ component) +
    ggplot2::labs(x = "Theoretical quantiles", y = "Residual quantiles") +
    ggplot2::theme_bw(base_size = 9)
}

#' Observed and simulated share of zero catches and mean density by year
#'
#' @param post Post-processed products.
#' @return ggplot with two rows (zero share, mean density) and one column per product.
plot_report_simulation <- function(post) {
  d <- purrr::imap_dfr(post, function(p, label) if (!is.null(p$sims)) dplyr::mutate(p$sims$year, product = label))
  long <- dplyr::bind_rows(
    dplyr::transmute(d, .data$product, .data$year, measure = "Share of zero catches",
                     obs = .data$obs_zero, sim = .data$sim_zero, lwr = .data$sim_zero_lwr, upr = .data$sim_zero_upr),
    dplyr::transmute(d, .data$product, .data$year, measure = "Mean density (kg/nmi²)",
                     obs = .data$obs_mean, sim = .data$sim_mean, lwr = .data$sim_mean_lwr, upr = .data$sim_mean_upr))
  long$product <- factor(long$product, names(post))
  ggplot2::ggplot(long, ggplot2::aes(.data$year)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lwr, ymax = .data$upr), fill = "grey75") +
    ggplot2::geom_line(ggplot2::aes(y = .data$sim), colour = "grey30") +
    ggplot2::geom_point(ggplot2::aes(y = .data$obs), colour = "#D55E00", size = 0.9) +
    ggplot2::facet_grid(measure ~ product, scales = "free_y", switch = "y") +
    ggplot2::labs(x = "Year", y = NULL) +
    ggplot2::theme_bw(base_size = 8) +
    ggplot2::theme(strip.placement = "outside", strip.background.y = ggplot2::element_blank())
}

#' Distribution of observed and simulated densities and of the predicted grid densities
#'
#' @param post Post-processed products.
#' @return ggplot: histograms of log(x + 1) densities, products in rows.
plot_report_density_hist <- function(post) {
  d <- purrr::imap_dfr(post, function(p, label) {
    if (is.null(p$sims)) return(NULL)
    dplyr::bind_rows(
      tibble::tibble(product = label, source = "Observed hauls", x = log1p(p$sims$haul$obs)),
      tibble::tibble(product = label, source = "Simulated hauls (mean)", x = log1p(p$sims$haul$sim)),
      tibble::tibble(product = label, source = "Prediction grid", x = log1p(exp(p$pred$est))))
  })
  d$product <- factor(d$product, names(post))
  d$source <- factor(d$source, c("Observed hauls", "Simulated hauls (mean)", "Prediction grid"))
  means <- dplyr::summarise(d, m = mean(.data$x), .by = c("product", "source"))
  ggplot2::ggplot(d, ggplot2::aes(.data$x)) +
    ggplot2::geom_histogram(bins = 40, fill = "grey60", colour = NA) +
    ggplot2::geom_vline(data = means, ggplot2::aes(xintercept = .data$m), colour = "#0072B2") +
    ggplot2::facet_grid(product ~ source, scales = "free_y") +
    ggplot2::scale_y_continuous(trans = "log1p", breaks = c(0, 10, 100, 1000, 10000)) +
    ggplot2::labs(x = "log(density + 1), density in kg/nmi²", y = "Count") +
    ggplot2::theme_bw(base_size = 8)
}

#' Indices of the products: absolute, scaled to the mean, and CV by year
#'
#' @param index_tab Long index table with a `model` column.
#' @return A three-panel figure.
plot_report_indices <- function(index_tab) {
  cols <- product_colours(levels(index_tab$model))
  base <- function(p) p + ggplot2::scale_colour_manual(values = cols) + ggplot2::scale_fill_manual(values = cols) +
    ggplot2::theme_bw(base_size = 9)
  a <- base(ggplot2::ggplot(index_tab, ggplot2::aes(.data$year, .data$est / 1000, colour = .data$model, fill = .data$model)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lwr / 1000, ymax = .data$upr / 1000), alpha = 0.15, colour = NA) +
    ggplot2::geom_line() + ggplot2::expand_limits(y = 0) +
    ggplot2::labs(x = NULL, y = "Biomass (t)", colour = NULL, fill = NULL)) +
    ggplot2::theme(legend.position = "none")
  rel <- index_tab |>
    dplyr::group_by(.data$model) |>
    dplyr::mutate(dplyr::across(c("est", "lwr", "upr"), ~ .x / mean(.data$est))) |>
    dplyr::ungroup()
  b <- base(ggplot2::ggplot(rel, ggplot2::aes(.data$year, .data$est, colour = .data$model, fill = .data$model)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lwr, ymax = .data$upr), alpha = 0.12, colour = NA) +
    ggplot2::geom_line() +
    ggplot2::labs(x = NULL, y = "Index / mean", colour = NULL, fill = NULL)) +
    ggplot2::theme(legend.position = "none")
  cvd <- dplyr::mutate(index_tab, cv = sqrt(exp(.data$se^2) - 1))
  c <- base(ggplot2::ggplot(cvd, ggplot2::aes(.data$year, .data$cv, colour = .data$model)) +
    ggplot2::geom_line() + ggplot2::geom_point(size = 0.8) +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, NA)) +
    ggplot2::labs(x = "Year", y = "CV", colour = NULL)) +
    ggplot2::theme(legend.position = "bottom")
  cowplot::plot_grid(a, b, c, ncol = 1, labels = "AUTO", rel_heights = c(1, 1, 1.25), align = "v", axis = "lr")
}

#' Fixed-effect or random-parameter table of all products
#'
#' @param post Post-processed products.
#' @param what "fixed" or "ran_pars".
#' @param component_names Names of the delta components.
#' @return A data frame for knitr::kable().
report_par_table <- function(post, what = c("fixed", "ran_pars"), component_names = c("Encounter", "Positive")) {
  what <- match.arg(what)
  fmt <- function(x) ifelse(is.na(x), "", formatC(x, digits = 3, format = "fg", flag = "#"))
  purrr::imap_dfr(post, function(p, label) {
    x <- p[[what]]
    if (is.null(x) || !nrow(x)) return(NULL)
    if (what == "fixed") x <- dplyr::filter(x, !grepl("^fyear", .data$term))
    lo <- if ("conf.low" %in% names(x)) x$conf.low else NA_real_
    hi <- if ("conf.high" %in% names(x)) x$conf.high else NA_real_
    tibble::tibble(Model = label, Component = component_names[x$component], Term = x$term,
                   Estimate = fmt(x$estimate), `95 % CI` = ifelse(is.na(lo), "", paste0(fmt(lo), " – ", fmt(hi))))
  })
}
