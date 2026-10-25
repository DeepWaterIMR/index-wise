#' Build a versioned assessment-index interchange object
#' @param index_products Named list of index data frames.
#' @param selected_name Exact configured product name.
#' @param metadata Units, uncertainty definition, type, timing, scope and provenance.
#' @return A schema-versioned list with observations and metadata.
build_assessment_index_handoff <- function(index_products, selected_name, metadata) {
  if (is.null(selected_name) || length(selected_name) != 1L || is.na(selected_name) ||
      !selected_name %in% names(index_products)) {
    stop("SELECTED_INDEX must exactly match a product in index_products: ",
         paste(names(index_products), collapse = ", "), call. = FALSE)
  }
  required_metadata <- c("units", "uncertainty", "index_type", "timing", "spatial_scope", "provenance")
  missing <- setdiff(required_metadata, names(metadata))
  if (length(missing)) stop("Assessment-index metadata missing: ", paste(missing, collapse = ", "), call. = FALSE)
  if (!is.list(metadata$uncertainty) || !identical(metadata$uncertainty$column, "se") ||
      !identical(metadata$uncertainty$scale, "log") || !identical(metadata$uncertainty$measure, "standard_error")) {
    stop("Uncertainty must identify se as standard_error on the log scale.", call. = FALSE)
  }
  if (!is.numeric(metadata$timing) || length(metadata$timing) != 1L ||
      !is.finite(metadata$timing) || metadata$timing < 0 || metadata$timing > 1) {
    stop("Index timing must be a fraction between 0 and 1.", call. = FALSE)
  }
  for (field in c("units", "index_type", "spatial_scope")) {
    value <- metadata[[field]]
    if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(trimws(value))) {
      stop("Missing index metadata value: ", field, call. = FALSE)
    }
  }
  if (!is.list(metadata$provenance) || !length(metadata$provenance)) stop("Record index provenance.", call. = FALSE)
  selected <- index_products[[selected_name]]
  if (!is.data.frame(selected) || !nrow(selected)) stop("Selected index is empty or is not a data frame.", call. = FALSE)
  required_columns <- c("year", "est", "lwr", "upr", "se")
  missing_columns <- setdiff(required_columns, names(selected))
  if (length(missing_columns)) stop("Selected index missing columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  if (!all(vapply(selected[required_columns], function(x) is.numeric(x) && all(is.finite(x)), logical(1))) ||
      anyDuplicated(selected$year) || any(selected$year != floor(selected$year)) ||
      any(selected$est <= 0) || any(selected$se <= 0) ||
      any(selected$lwr > selected$est | selected$upr < selected$est)) {
    stop("Index needs unique integer years, positive estimates/log SEs and finite ordered intervals.", call. = FALSE)
  }
  list(schema_version = 1L, selected_name = selected_name,
       observations = dplyr::select(selected, dplyr::all_of(required_columns)),
       metadata = metadata)
}
