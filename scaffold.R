# scaffold.R — instantiate a new index project from project-template/
#
# Copies the project-template/ skeleton into a target directory, renames the SPECIES
# folder/files to the species slug, and stamps {{PLACEHOLDER}} identity tokens from a
# config.yaml. Analytical settings (CRS, grid size, mesh cutoff, length groups, …) are NOT
# hard-stamped — the documents read them from config.yaml at run time via R/0_setup.R. Only
# identity and path-shaping tokens are stamped here.
#
# Usage:
#   source("<index_template_path>/scaffold.R")
#   scaffold_index(config = "config.yaml", target = "../snabeluer-index")             # do it
#   scaffold_index(config = "config.yaml", target = "../snabeluer-index", dry = TRUE)  # preview
#   # If the template can't be auto-located, pass it explicitly:
#   scaffold_index("config.yaml", "../snabeluer-index", template = "<path>/project-template")
#
# Requires: yaml. (install.packages("yaml"))

# --- Read a YAML file as UTF-8, independent of the R locale ----------------------------
.read_yaml_utf8 <- function(path) {
  txt <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  yaml::yaml.load(txt)
}

# --- Locate the project-template/ directory -------------------------------------------
# Order: explicit arg -> ~/.index-wise/config.json -> legacy
# ~/.index-template/config.json -> ./project-template -> error.
.find_template <- function(template = NULL) {
  if (!is.null(template) && dir.exists(template)) return(normalizePath(template))

  cfg_jsons <- path.expand(c("~/.index-wise/config.json",
                             "~/.index-template/config.json"))
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    for (cfg_json in cfg_jsons[file.exists(cfg_jsons)]) {
      p <- tryCatch(jsonlite::read_json(cfg_json)$index_template_path,
                    error = function(e) NULL)
      if (!is.null(p)) {
        cand <- file.path(p, "project-template")
        if (dir.exists(cand)) return(normalizePath(cand))
      }
    }
  }

  cand <- file.path(getwd(), "project-template")
  if (dir.exists(cand)) return(normalizePath(cand))

  stop("Cannot locate project-template/. Pass it explicitly via `template=`.")
}

scaffold_index <- function(config, target, template = NULL, dry = FALSE) {

  if (!requireNamespace("yaml", quietly = TRUE))
    stop("The 'yaml' package is required: install.packages('yaml')")

  template <- .find_template(template)
  msg <- function(...) cat(if (dry) "[dry] " else "", ..., "\n", sep = "")

  # --- Read and validate the config ---------------------------------------------------
  # Read as UTF-8 bytes so Norwegian species names (å/æ/ø) parse regardless of R locale.
  cfg <- .read_yaml_utf8(config)
  required <- c("SPECIES_NAME", "SPECIES_SLUG", "SPECIES_LATIN", "FILTER_SP")
  miss <- setdiff(required, names(cfg))
  if (length(miss)) stop("config.yaml is missing required keys: ", paste(miss, collapse = ", "))

  slug <- cfg$SPECIES_SLUG
  if (!grepl("^[a-z0-9-]+$", slug))
    stop("SPECIES_SLUG must be lower-case kebab-case (a-z, 0-9, -): got '", slug, "'")

  # Regions are optional for single-domain projects, but when a project is split by region
  # the region slug belongs in data-document filenames to keep N62/S62 outputs unambiguous.
  region_slug <- if (!is.null(cfg$REGION_SLUG)) as.character(cfg$REGION_SLUG) else "all"
  if (!grepl("^[A-Za-z0-9-]+$", region_slug))
    stop("REGION_SLUG must contain only letters, numbers, and hyphens: got '", region_slug, "'")

  # Human metadata follows wise-writing's config schema. YAML serialization preserves
  # punctuation, Unicode, and multiple authors without treating their names as YAML code.
  if (!length(cfg$AUTHORS) || !length(cfg$AFFILIATIONS))
    stop("Supply accountable human AUTHORS and AFFILIATIONS in config.yaml before scaffolding.")
  valid_name <- function(x) is.list(x) && is.character(x$name) &&
    length(x$name) == 1L && !is.na(x$name) && nzchar(trimws(x$name))
  if (!all(vapply(c(cfg$AUTHORS, cfg$AFFILIATIONS), valid_name, logical(1))))
    stop("Every author and affiliation must have a non-empty name.")
  affiliation_ids <- vapply(cfg$AFFILIATIONS, function(x) {
    if (is.null(x$id)) "" else as.character(x$id)
  }, character(1))
  if (any(!nzchar(affiliation_ids)) || anyDuplicated(affiliation_ids))
    stop("AFFILIATIONS must have unique non-empty IDs.")
  author_refs <- lapply(cfg$AUTHORS, function(x) unlist(x$affiliation, use.names = FALSE))
  if (any(lengths(author_refs) == 0L) ||
      !all(unlist(author_refs, use.names = FALSE) %in% affiliation_ids))
    stop("Each author must reference a configured affiliation ID.")
  authors <- lapply(seq_along(cfg$AUTHORS), function(i) {
    author <- cfg$AUTHORS[[i]]
    author$affiliation <- NULL
    author$affiliations <- lapply(author_refs[[i]], function(id) list(ref = id))
    if (is.null(author$corresponding)) author$corresponding <- i == 1L
    author
  })
  yaml_block <- function(x) paste0("\n", paste0("  ",
    strsplit(trimws(yaml::as.yaml(x, handlers = list(logical = function(value)
      structure(ifelse(value, "true", "false"), class = "verbatim")))),
      "\n", fixed = TRUE)[[1]], collapse = "\n"))

  # --- Copy the skeleton --------------------------------------------------------------
  if (dir.exists(target) && length(list.files(target, all.files = TRUE, no.. = TRUE)))
    stop("Target '", target, "' exists and is not empty. Choose an empty/new directory.")

  if (!dry) {
    dir.create(target, recursive = TRUE, showWarnings = FALSE)
    file.copy(list.files(template, full.names = TRUE, all.files = TRUE, no.. = TRUE),
              target, recursive = TRUE, copy.mode = TRUE)
    file.copy(config, file.path(target, "config.yaml"), overwrite = TRUE)
  }
  msg("Copied project-template/ -> ", target)

  # --- Rename SPECIES folder and SPECIES-* files to the slug --------------------------
  if (!dry) {
    sp_dir <- file.path(target, "docs", "data-report", "SPECIES")
    if (dir.exists(sp_dir)) file.rename(sp_dir, file.path(target, "docs", "data-report", slug))
    for (f in list.files(target, recursive = TRUE, full.names = TRUE)) {
      if (grepl("SPECIES", basename(f)))
        file.rename(f, file.path(dirname(f), gsub("SPECIES", slug, basename(f))))
    }
    for (f in list.files(target, recursive = TRUE, full.names = TRUE)) {
      if (grepl("\\{\\{REGION_SLUG\\}\\}", basename(f)))
        file.rename(f, file.path(dirname(f), gsub("\\{\\{REGION_SLUG\\}\\}", region_slug, basename(f))))
    }
  }
  msg("Renamed SPECIES -> ", slug, " and region -> ", region_slug, " in paths")

  # --- Stamp identity tokens in text files --------------------------------------------
  tokens <- c(
    "{{SPECIES_NAME}}"  = as.character(cfg$SPECIES_NAME),
    "{{SPECIES_SLUG}}"  = as.character(cfg$SPECIES_SLUG),
    "{{SPECIES_LATIN}}" = as.character(cfg$SPECIES_LATIN),
    "{{REGION_SLUG}}"   = region_slug,
    "{{AUTHORS_YAML}}" = yaml_block(authors),
    "{{AFFILIATIONS_YAML}}" = yaml_block(cfg$AFFILIATIONS)
  )
  text_ext <- c("qmd", "rmd", "r", "md", "yaml", "yml", "css", "bib")
  scan_root <- if (dry) template else target
  files <- list.files(scan_root, recursive = TRUE, full.names = TRUE)
  files <- files[tolower(tools::file_ext(files)) %in% text_ext]

  for (f in files) {
    txt <- tryCatch({
      s <- readChar(f, file.info(f)$size, useBytes = TRUE); Encoding(s) <- "UTF-8"; s
    }, error = function(e) NULL)
    if (is.null(txt)) next
    new <- txt
    for (tok in names(tokens)) new <- gsub(tok, tokens[[tok]], new, fixed = TRUE)
    if (!dry && !identical(new, txt))
      writeBin(charToRaw(enc2utf8(new)), f)
  }
  msg("Stamped identity tokens (SPECIES_NAME/SLUG/LATIN)")

  if (!dry) {
    writeLines(c("version: 0.1.0", paste0("date: ", Sys.Date())),
               file.path(target, "VERSION"))
  }

  # --- Sanity check: no leftover identity placeholders --------------------------------
  if (!dry) {
    left <- character()
    for (f in files) {
      txt <- tryCatch({
        s <- readChar(f, file.info(f)$size, useBytes = TRUE); Encoding(s) <- "UTF-8"; s
      }, error = function(e) "")
      if (grepl("\\{\\{(SPECIES_(NAME|SLUG|LATIN)|REGION_SLUG)\\}\\}", txt)) left <- c(left, f)
    }
    if (length(left))
      warning("Leftover identity placeholders in:\n  ", paste(left, collapse = "\n  "))
    else
      msg("No leftover identity placeholders.")
    message("Scaffolded '", cfg$SPECIES_NAME, "' at: ", normalizePath(target))
    message("Next: review config.yaml, then run Step 1 (index-compile-data).")
  }

  invisible(target)
}
