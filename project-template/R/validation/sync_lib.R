# Pure helpers of R/validation/sync_final_model.R: the grid decision and a line-based edit of
# config.yaml that keeps its comments and layout. No model packages needed (tested in
# index-wise config/test-validation-helpers.R).

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Coarsest prediction grid whose index stays within `tol` of the finest grid's index
#'
#' @param gi Grid-stage index (year, est, grid_km).
#' @param current Current GRID_KM; kept while it passes.
#' @param tol Tolerance on the terminal-year difference, the mean difference over the last
#'   `window` years and the mean absolute relative difference.
#' @param window Years in the end-of-series mean.
#' @return The grid size (km).
grid_decision <- function(gi, current = NULL, tol = 0.01, window = 5) {
  ref <- gi[gi$grid_km == min(gi$grid_km), c("year", "est")]
  names(ref)[2] <- "ref"
  last <- max(gi$year)
  m <- merge(gi, ref, by = "year")
  m$r <- m$est / m$ref - 1
  tab <- do.call(rbind, lapply(split(m, m$grid_km), function(x) data.frame(
    grid_km = x$grid_km[1], terminal = x$r[x$year == last],
    rho = mean(x$r[x$year > last - window]), mard = mean(abs(x$r)))))
  tab$stable <- abs(tab$terminal) <= tol & abs(tab$rho) <= tol & tab$mard <= tol
  if (!is.null(current) && isTRUE(tab$stable[tab$grid_km == current])) return(current)
  max(tab$grid_km[tab$stable])
}

# YAML scalar or flow sequence of strings.
yaml_vec <- function(x) {
  x <- unlist(x)
  if (length(x) == 1L) paste0('"', x, '"') else paste0("[", paste0('"', x, '"', collapse = ", "), "]")
}

#' Edit config.yaml lines with the selection's decisions
#'
#' @param lines Lines of config.yaml.
#' @param key Stock key: the SPECIES_SETTINGS entry, or the single stock of a flat config.
#' @param d Decisions (decisions.rds of the selection).
#' @param grid_km Selected grid size, or NULL.
#' @return A list with the new `lines`, the applied `new` values, the `changes` and the
#'   decisions that could not be applied (`problems`).
sync_config_lines <- function(lines, key, d, grid_km = NULL) {
  problems <- c(
    if (isTRUE(d$barrier)) "barrier mesh selected; the report has no barrier mesh",
    if (!is.null(d$positive_terms)) "separate positive-component terms selected; the report uses one formula",
    if (!isTRUE(d$year)) "model without a year factor selected; the assessment index needs it"
  )
  family_name <- function(x) sub("_poisson$", "_poisson_link", x)
  new <- list(
    MESH_CUTOFF_KM = format(as.numeric(d$mesh_km)),
    TERMS = paste0("[", paste0('"', unlist(d$terms), '"', collapse = ", "), "]"),
    FAMILY = paste0('"', family_name(d$family), '"'),
    SPATIAL = yaml_vec(d$spatial),
    SPATIOTEMPORAL = yaml_vec(d$spatiotemporal),
    ANISOTROPY = tolower(as.character(isTRUE(d$anisotropy)))
  )
  changes <- character()
  indent_of <- function(x) nchar(sub("^( *).*$", "\\1", x))
  content <- function(x) grepl("^\\s*[^#[:space:]]", x)

  # The block that holds the stock's settings, and its indent.
  ss <- grep("^SPECIES_SETTINGS:", lines)
  if (length(ss)) {
    start <- grep(paste0("^  ", key, ":\\s*(#.*)?$"), lines)
    start <- start[start > ss][1]
    if (is.na(start)) stop("No SPECIES_SETTINGS entry '", key, "' in config.yaml.")
    after <- which(seq_along(lines) > start & content(lines) & indent_of(lines) <= 2)
    end <- min(c(after, length(lines) + 1)) - 1
    ind <- "    "
  } else {
    start <- 0
    end <- length(lines)
    ind <- ""
  }
  find <- function(k, from, to, indent) {
    i <- grep(paste0("^", indent, k, ":"), lines)
    i[i > from & i <= to]
  }
  set_value <- function(i, value) {
    m <- regmatches(lines[i], regexec("^(\\s*[A-Z_]+:\\s*)([^#]*?)(\\s*#.*)?$", lines[i]))[[1]]
    if (trimws(m[3]) != value) {
      changes <<- c(changes, paste0(trimws(m[2]), " ", trimws(m[3]), " -> ", value))
      lines[i] <<- paste0(m[2], value, if (nzchar(m[4])) m[4] else "")
    }
  }
  insert <- function(after, new_lines, note) {
    lines <<- append(lines, new_lines, after = after)
    end <<- end + length(new_lines)
    changes <<- c(changes, note)
  }
  block_end <- function(i, indent_n) {   # last child line of the mapping at line i
    after <- which(seq_along(lines) > i & content(lines) & indent_of(lines) <= indent_n)
    min(c(after, end + 1)) - 1
  }

  # FINAL_MODEL: update the children, or write the whole block.
  fm <- find("FINAL_MODEL", start, end, ind)
  child <- paste0(ind, "  ")
  if (length(fm) == 1L && grepl("^\\s*FINAL_MODEL:\\s*(#.*)?$", lines[fm])) {
    for (k in names(new)) {
      i <- find(k, fm, block_end(fm, nchar(ind)), child)
      if (length(i) == 1L) set_value(i, new[[k]]) else
        insert(block_end(fm, nchar(ind)), paste0(child, k, ": ", new[[k]]), paste0("FINAL_MODEL$", k, " -> ", new[[k]]))
    }
  } else {
    blk <- c(paste0(ind, "FINAL_MODEL:                      # written by R/validation/sync_final_model.R"),
             paste0(child, names(new), ": ", unlist(new)))
    if (length(fm) == 1L) {
      lines <- lines[-fm]
      end <- end - 1
      insert(fm - 1, blk, "FINAL_MODEL (new block)")
    } else {
      insert(end, blk, "FINAL_MODEL (new block)")
    }
  }

  # Mesh cutoff and grid size beside FINAL_MODEL, in the same block.
  put <- function(k, value, note) {
    i <- find(k, start, end, ind)
    i <- i[!vapply(i, function(j) any(seq(start + 1, j - 1) %in% find("FINAL_MODEL", start, end, ind) &
                                         j <= block_end(find("FINAL_MODEL", start, end, ind)[1], nchar(ind))), logical(1))]
    if (length(i) >= 1L) set_value(i[1], value) else insert(end, paste0(ind, k, ": ", value, "  # ", note), paste0(k, " -> ", value))
  }
  put("MESH_CUTOFF_KM", new$MESH_CUTOFF_KM, "selected in the mesh stage")
  if (!is.null(grid_km)) put("GRID_KM", format(grid_km), "selected in the grid stage")
  if (!is.null(d$smoothed)) {
    put("SMOOTHED_SPATIAL", yaml_vec(d$smoothed$spatial), "selected in the fields stage")
    put("SMOOTHED_SPATIOTEMPORAL", yaml_vec(d$smoothed$spatiotemporal), "selected in the fields stage")
  }
  list(lines = lines, new = new, changes = changes, problems = problems)
}
