# Build the versioned assessment-index interchange object from an explicitly selected product.
build_assessment_index_handoff <- function(index_products, selected_name, metadata) {
  if (is.null(selected_name) || length(selected_name) != 1L || is.na(selected_name) ||
      !selected_name %in% names(index_products)) {
    stop("SELECTED_INDEX must exactly match a product in index_products: ",
         paste(names(index_products), collapse = ", "), call. = FALSE)
  }
  required_metadata <- c("units", "uncertainty", "index_type", "timing", "spatial_scope", "provenance")
  missing <- setdiff(required_metadata, names(metadata))
  if (length(missing)) stop("Assessment-index metadata missing: ", paste(missing, collapse = ", "), call. = FALSE)
  selected <- index_products[[selected_name]]
  required_columns <- c("year", "est", "lwr", "upr", "se")
  missing_columns <- setdiff(required_columns, names(selected))
  if (length(missing_columns)) stop("Selected index missing columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  list(schema_version = 1L, selected_name = selected_name,
       observations = dplyr::select(selected, dplyr::all_of(required_columns)),
       metadata = metadata)
}
