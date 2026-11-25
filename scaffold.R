# scaffold.R — instantiate a new index project from project-template/
#
# Copies the project-template/ skeleton into a target directory, writes one copy of every
# per-stock document (STOCK-* files and the STOCK folder) for each stock, and stamps
# {{PLACEHOLDER}} identity tokens from a config.yaml. Analytical settings (CRS, grid size, mesh cutoff, length groups, …) are NOT
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
# Document-folder root (DOCS_DIR): the template's docs/{assets,background,data,sdmtmb} go to
# `docs/` by default, or to `docs/benchmark/` for an index made for a stock assessment
# (docs/render.R always stays at docs/render.R). Resolution order:
#   1. the `docs_dir` argument, e.g. scaffold_index(..., docs_dir = "docs/assessment-2027");
#   2. DOCS_DIR in the config when it is not the plain default "docs";
#   3. "docs/benchmark" when the config names an ASSESSMENT_MODEL (not empty/null/"none");
#   4. "docs".
# Pass docs_dir = "docs" to force the flat layout for an index that has an ASSESSMENT_MODEL.
# The chosen value is written to DOCS_DIR in the project's config.yaml.
#
# Stocks: a config without SPECIES_SETTINGS is one stock, keyed by STOCK_SLUG (default the
# species slug, plus the region slug for a split domain). With SPECIES_SETTINGS each entry is a
# stock keyed by its name; its settings override the shared ones. Every stock gets its own
# numbered documents (<key>-0-background.qmd ... <key>-6-report.qmd); the first stock's
# documents are the masters for ai/tests/test-stock-parity.R.
#
# Requires: yaml. (install.packages("yaml"))

# --- Read a YAML file as UTF-8, independent of the R locale ----------------------------
.read_yaml_utf8 <- function(path) {
  txt <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  yaml::yaml.load(txt, eval.expr = FALSE)
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

# Generated projects carry their own copy of wise-writing's shared loader. Resolve it from
# the installed pack first, then a side-by-side checkout for standalone development use.
.find_package_setup <- function(template) {
  candidates <- character()
  configs <- path.expand(c("~/.wise-writing/config.json", "~/.academic-writing/config.json"))
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    for (config in configs[file.exists(configs)]) {
      pack <- tryCatch(jsonlite::read_json(config)$academic_writing_path,
                       error = function(e) NULL)
      if (!is.null(pack)) candidates <- c(candidates,
        file.path(pack, "project-template", "R", "package_setup.R"))
    }
  }

  pack_root <- dirname(normalizePath(template, mustWork = TRUE))
  candidates <- c(candidates,
    file.path(dirname(pack_root), "wise-writing", "project-template", "R", "package_setup.R"),
    file.path(dirname(pack_root), "academic-writing", "project-template", "R", "package_setup.R"))

  found <- candidates[file.exists(candidates)]
  if (length(found)) return(normalizePath(found[[1]]))
  stop("Cannot locate wise-writing's R/package_setup.R. Install wise-writing or place its checkout beside index-wise.",
       call. = FALSE)
}

# Resolve the document-folder root (see the header). Returns a relative path under docs/.
.resolve_docs_dir <- function(cfg, docs_dir = NULL) {
  assessment <- !is.null(cfg$ASSESSMENT_MODEL) && length(cfg$ASSESSMENT_MODEL) == 1L &&
    !is.na(cfg$ASSESSMENT_MODEL) && nzchar(trimws(cfg$ASSESSMENT_MODEL)) &&
    !tolower(trimws(cfg$ASSESSMENT_MODEL)) %in% c("none", "null", "no")
  cfg_dir <- if (!is.null(cfg$DOCS_DIR) && !grepl("^\\{\\{", cfg$DOCS_DIR))
    sub("/+$", "", as.character(cfg$DOCS_DIR)) else "docs"
  out <- if (!is.null(docs_dir)) sub("/+$", "", docs_dir)
         else if (!identical(cfg_dir, "docs")) cfg_dir
         else if (assessment) "docs/benchmark"
         else "docs"
  if (!grepl("^docs(/[A-Za-z0-9._-]+)*$", out) || grepl("(^|/)\\.\\.?(/|$)", out))
    stop("docs_dir/DOCS_DIR must be 'docs' or a subfolder such as 'docs/benchmark': got '",
         out, "'", call. = FALSE)
  out
}

# The stocks of a config: a named list (key = file prefix and output folder) of the merged
# settings of each stock, with its `area_label`. Stops on missing identity keys or bad keys.
.resolve_stocks <- function(cfg, region_slug = "all") {
  shared <- cfg[setdiff(names(cfg), "SPECIES_SETTINGS")]
  blocks <- cfg$SPECIES_SETTINGS
  if (is.null(blocks)) {
    slug <- cfg$SPECIES_SLUG
    key <- if (!is.null(cfg$STOCK_SLUG) && !grepl("^\\{\\{", cfg$STOCK_SLUG)) {
      as.character(cfg$STOCK_SLUG)
    } else if (!is.null(slug) && !region_slug %in% c("all", "ALL")) {
      tolower(paste(slug, region_slug, sep = "-"))
    } else slug
    blocks <- stats::setNames(list(list()), if (is.null(key)) "" else key)
  }
  if (!length(blocks)) stop("SPECIES_SETTINGS is empty.")
  out <- lapply(names(blocks), function(key) {
    st <- utils::modifyList(shared, blocks[[key]] %||% list())
    miss <- setdiff(c("SPECIES_NAME", "SPECIES_SLUG", "SPECIES_LATIN", "FILTER_SP"), names(st))
    if (length(miss)) stop("Stock '", key, "' is missing required keys: ", paste(miss, collapse = ", "))
    if (!grepl("^[a-z0-9-]+$", key))
      stop("Stock keys (STOCK_SLUG, or SPECIES_SETTINGS names) must be lower-case kebab-case: got '", key, "'")
    if (!grepl("^[a-z0-9-]+$", st$SPECIES_SLUG))
      stop("SPECIES_SLUG must be lower-case kebab-case (a-z, 0-9, -): got '", st$SPECIES_SLUG, "'")
    st$area_label <- if (!is.null(st$AREA_LABEL) && !grepl("^\\{\\{", st$AREA_LABEL)) {
      as.character(st$AREA_LABEL)
    } else if (length(st$STOCK_SUBAREAS)) {
      paste0("ICES ", paste(unlist(st$STOCK_SUBAREAS), collapse = "\u2013"))
    } else if (!is.null(st$REGION)) as.character(st$REGION) else "all"
    st
  })
  stats::setNames(out, names(blocks))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# `docs_dir`: root of the document folders inside the project; NULL = derive from the config
# (see the header: DOCS_DIR, else docs/benchmark for an assessment index, else docs).
scaffold_index <- function(config, target, template = NULL, dry = FALSE, docs_dir = NULL) {

  if (!requireNamespace("yaml", quietly = TRUE))
    stop("The 'yaml' package is required: install.packages('yaml')")

  template <- .find_template(template)
  package_setup_source <- .find_package_setup(template)
  msg <- function(...) cat(if (dry) "[dry] " else "", ..., "\n", sep = "")

  # --- Read and validate the config ---------------------------------------------------
  # Read as UTF-8 bytes so Norwegian species names (å/æ/ø) parse regardless of R locale.
  cfg <- .read_yaml_utf8(config)
  docs_dir <- .resolve_docs_dir(cfg, docs_dir)
  # Regions are optional for single-domain projects, but when a project is split by region
  # the region slug belongs in document filenames to keep N62/S62 outputs unambiguous.
  region_slug <- if (!is.null(cfg$REGION_SLUG)) as.character(cfg$REGION_SLUG) else "all"
  stocks <- .resolve_stocks(cfg, region_slug)
  slug <- stocks[[1]]$SPECIES_SLUG
  stock_slug <- names(stocks)[1]
  area_label <- stocks[[1]]$area_label
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
    dir.create(file.path(target, "R"), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(package_setup_source, file.path(target, "R", "package_setup.R"),
                   overwrite = TRUE)) {
      stop("Failed to copy wise-writing's package_setup.R into the scaffolded project.")
    }
    file.copy(config, file.path(target, "config.yaml"), overwrite = TRUE)

    # Record DOCS_DIR in the project's config (replace the line, or add it when the supplied
    # config predates the key).
    cfg_path <- file.path(target, "config.yaml")
    ctxt <- readChar(cfg_path, file.info(cfg_path)$size, useBytes = TRUE)
    Encoding(ctxt) <- "UTF-8"
    dline <- paste0('DOCS_DIR: "', docs_dir, '"')
    if (grepl("(^|\n)DOCS_DIR:[^\n]*", ctxt)) {
      ctxt <- sub("(^|\n)DOCS_DIR:[^\n]*", paste0("\\1", dline), ctxt)
    } else {
      ctxt <- paste0(sub("\n*$", "\n", ctxt), dline,
                     "   # root of the document folders (assets, background, data, sdmtmb)\n")
    }
    # A single-stock config records its stock key, so that R/0_setup.R finds the documents'
    # `index_species` (the key may come from SPECIES_SLUG + REGION_SLUG).
    if (is.null(cfg$SPECIES_SETTINGS) && !grepl("(^|\n)STOCK_SLUG:\\s*\"[a-z0-9-]+\"", ctxt)) {
      sline <- paste0('STOCK_SLUG: "', stock_slug, '"')
      ctxt <- if (grepl("(^|\n)STOCK_SLUG:[^\n]*", ctxt)) {
        sub("(^|\n)STOCK_SLUG:[^\n]*", paste0("\\1", sline), ctxt)
      } else paste0(sub("\n*$", "\n", ctxt), sline, "   # stock key: document prefix and output folder\n")
    }
    writeBin(charToRaw(enc2utf8(ctxt)), cfg_path)

    # Nest the document folders under docs_dir (render.R stays at docs/render.R).
    if (!identical(docs_dir, "docs")) {
      dir.create(file.path(target, docs_dir), recursive = TRUE, showWarnings = FALSE)
      for (d in c("assets", "background", "data", "sdmtmb")) {
        from <- file.path(target, "docs", d)
        if (dir.exists(from)) file.rename(from, file.path(target, docs_dir, d))
      }
    }
  }
  msg("Copied project-template/ -> ", target, " (document folders in ", docs_dir, "/)")

  # --- One copy of every per-stock document for each stock ----------------------------
  # Files named STOCK-* and the folder docs/.../sdmtmb/STOCK become <key>-* and <key>/; each
  # copy is stamped with its stock's identity. Shared files get the first stock's tokens.
  text_ext <- c("qmd", "rmd", "r", "md", "yaml", "yml", "css", "bib")
  read_utf8 <- function(f) tryCatch({
    s <- readChar(f, file.info(f)$size, useBytes = TRUE); Encoding(s) <- "UTF-8"; s
  }, error = function(e) NULL)
  stamp <- function(txt, tokens) {
    for (tok in names(tokens)) txt <- gsub(tok, tokens[[tok]], txt, fixed = TRUE)
    txt
  }
  tokens_for <- function(st, key) c(
    "{{SPECIES_NAME}}"  = as.character(st$SPECIES_NAME),
    "{{SPECIES_SLUG}}"  = as.character(st$SPECIES_SLUG),
    "{{SPECIES_LATIN}}" = as.character(st$SPECIES_LATIN),
    "{{STOCK_KEY}}"     = key,
    "{{STOCK_SLUG}}"    = key,
    "{{REGION_SLUG}}"   = region_slug,
    "{{AREA_LABEL}}"    = enc2utf8(st$area_label),
    "{{AUTHORS_YAML}}" = yaml_block(authors),
    "{{AFFILIATIONS_YAML}}" = yaml_block(cfg$AFFILIATIONS)
  )
  root <- if (dry) template else target
  all_files <- list.files(root, recursive = TRUE, full.names = TRUE)
  rel <- substring(all_files, nchar(root) + 2)
  per_stock <- grepl("(^|/)STOCK(-|/)", rel)
  if (!dry) {
    for (i in which(per_stock)) {
      for (key in names(stocks)) {
        # Twice: in "STOCK/STOCK-6" the first match consumes the slash the second needs.
        new_rel <- rel[i]
        for (pass in 1:2) new_rel <- sub("(^|/)STOCK(-|/)", paste0("\\1", key, "\\2"), new_rel)
        to <- file.path(target, new_rel)
        dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
        txt <- if (tolower(tools::file_ext(to)) %in% text_ext) read_utf8(all_files[i]) else NULL
        if (is.null(txt)) file.copy(all_files[i], to, overwrite = TRUE) else
          writeBin(charToRaw(enc2utf8(stamp(txt, tokens_for(stocks[[key]], key)))), to)
      }
      unlink(all_files[i])
    }
    for (d in list.dirs(target, recursive = TRUE)) if (basename(d) == "STOCK") unlink(d, recursive = TRUE)
    for (f in all_files[!per_stock & tolower(tools::file_ext(all_files)) %in% text_ext]) {
      txt <- read_utf8(f)
      if (is.null(txt)) next
      new <- stamp(txt, tokens_for(stocks[[1]], names(stocks)[1]))
      if (!identical(new, txt)) writeBin(charToRaw(enc2utf8(new)), f)
    }
  }
  msg("Wrote the per-stock documents for: ", paste(names(stocks), collapse = ", "))
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  files <- files[tolower(tools::file_ext(files)) %in% text_ext]

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
      if (grepl("\\{\\{(SPECIES_(NAME|SLUG|LATIN)|REGION_SLUG|STOCK_SLUG|STOCK_KEY|AREA_LABEL)\\}\\}", txt)) left <- c(left, f)
    }
    if (length(left))
      warning("Leftover identity placeholders in:\n  ", paste(left, collapse = "\n  "))
    else
      msg("No leftover identity placeholders.")
    message("Scaffolded ", paste(vapply(stocks, `[[`, "", "SPECIES_NAME"), collapse = ", "),
            " at: ", normalizePath(target))
    message("Next: review config.yaml, then run Step 1 (index-compile-data).")
  }

  invisible(target)
}
