# report_helpers.R — software citations, sanity sentences and parameter formatting for the reports.

#' Cite the installed software used by a report
#'
#' Writes report-specific BibTeX from citation() and emits narrative citations with
#' installed versions. Keep literature references in docs/assets/references.bib.
#' @param packages Character vector of packages that influenced this report.
#' @param bibliography Path to this report's generated software bibliography.
#' @return Invisibly, the generated BibTeX entries.
report_software <- function(packages, bibliography) {
  packages <- unique(c("base", packages))
  entries <- character()
  prose <- character()
  for (package in packages) {
    refs <- utils::citation(package)
    keys <- paste0("software-", gsub("[^A-Za-z0-9]", "", package), "-", seq_along(refs))
    for (i in seq_along(refs)) {
      ref <- refs[i]
      ref$key <- keys[i]
      entries <- c(entries, as.character(utils::toBibtex(ref)), "")
    }
    label <- if (package == "base") "R" else package
    version <- if (package == "base") as.character(getRversion()) else
      as.character(utils::packageVersion(package))
    prose <- c(prose, paste0(label, " ", version, " [",
                            paste0("@", keys, collapse = "; "), "]"))
  }
  dir.create(dirname(bibliography), recursive = TRUE, showWarnings = FALSE)
  writeLines(entries, bibliography, useBytes = TRUE)
  cat("The analysis and report used ", paste(prose, collapse = ", "), ".\n\n", sep = "")
  invisible(entries)
}

#' Describe sanity() results in a sentence generated from the fits
#'
#' Never hard-code "all models passed": place this inline after the sanity table.
#' @param fits Named list of sdmTMB fits.
#' @return A character string.
sanity_sentence <- function(fits) {
  check_labels <- c(
    hessian_ok = "non-positive-definite Hessian", eigen_values_ok = "small Hessian eigenvalues",
    nlminb_ok = "optimiser did not converge", range_ok = "range larger than the domain",
    gradients_ok = "large gradients", se_magnitude_ok = "large standard errors",
    se_na_ok = "missing standard errors", sigmas_ok = "near-zero variance parameters"
  )
  failed <- purrr::map(fits, function(fit) {
    s <- suppressMessages(sdmTMB::sanity(fit, silent = TRUE))
    checks <- intersect(names(check_labels), names(s))
    unname(check_labels[checks[!unlist(s[checks])]])
  })
  n_ok <- sum(lengths(failed) == 0)
  if (n_ok == length(fits)) {
    return(paste0("All ", length(fits), " models passed the sanity checks."))
  }
  bad <- failed[lengths(failed) > 0]
  paste0(n_ok, " of ", length(fits), " models passed the sanity checks. ",
         paste0(names(bad), ": ", purrr::map_chr(bad, paste, collapse = ", "),
                collapse = "; "), ".")
}

#' Format parameter estimates and CIs for tables
#'
#' Near-zero variance terms give upper CIs of Inf or ~1e172; fixed notation then prints a
#' 173-digit number that pushes a LaTeX longtable off the page.
#' @param x Numeric vector.
#' @param digits Significant digits.
#' @return Character vector; values >= 1e4 in scientific notation.
format_par_value <- function(x, digits = 3) {
  dplyr::case_when(
    is.na(x) ~ NA_character_,
    is.infinite(x) ~ ifelse(x > 0, "Inf", "-Inf"),
    abs(x) >= 1e4 ~ formatC(x, format = "e", digits = digits - 1),
    TRUE ~ trimws(formatC(signif(x, digits), format = "fg", digits = digits))
  )
}
