#!/usr/bin/env Rscript
# lint_project.R — mechanical checks for an index-wise project (or the project template).
#
# Usage: Rscript lint_project.R [project-root] [--template]
#
# Prints one line per finding: SEVERITY<TAB>check<TAB>file:line<TAB>message.
# Severity: ERROR (almost certainly a bug), WARN (likely wrong, verify), INFO (review by hand).
# The script only reads files. It needs base R; the yaml package is used when installed.
# It does not replace the reading review in the index-review skill: it finds the mechanical
# defects so the reading review can concentrate on meaning.

args <- commandArgs(trailingOnly = TRUE)
template_mode <- "--template" %in% args
args <- setdiff(args, "--template")
root <- normalizePath(if (length(args)) args[[1]] else ".", mustWork = TRUE)
setwd(root)

findings <- list()
add <- function(severity, check, file, line, message) {
  findings[[length(findings) + 1]] <<- data.frame(
    severity = severity, check = check,
    where = if (is.na(line)) file else paste0(file, ":", line),
    message = message, stringsAsFactors = FALSE
  )
}

# --- Files ---------------------------------------------------------------------------------

tracked <- tryCatch(
  system2("git", c("ls-files"), stdout = TRUE, stderr = FALSE),
  error = function(e) character(), warning = function(w) character()
)
in_git <- length(tracked) > 0
all_files <- if (in_git) tracked else list.files(".", recursive = TRUE, all.files = FALSE)
all_files <- all_files[file.exists(all_files)]
skip_dirs <- "^(renv|\\.quarto|_site|_freeze|node_modules|.*_files)/"
all_files <- all_files[!grepl(skip_dirs, all_files)]

code_files <- all_files[grepl("\\.(R|r|qmd|Rmd|sh)$", all_files)]
r_files <- all_files[grepl("\\.(R|r)$", all_files)]
doc_files <- all_files[grepl("\\.(qmd|Rmd)$", all_files)]
bib_files <- all_files[grepl("\\.bib$", all_files)]

read_lines <- function(f) {
  x <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  iconv(x, "UTF-8", "UTF-8", sub = "?")
}
text <- setNames(lapply(code_files, read_lines), code_files)

# Lines of a qmd/Rmd split into prose and chunk code; YAML front matter counts as neither.
classify_doc <- function(lines) {
  type <- rep("prose", length(lines))
  in_chunk <- FALSE
  fence <- ""
  if (length(lines) && grepl("^---\\s*$", lines[[1]])) {
    end <- which(grepl("^---\\s*$", lines))[2]
    if (!is.na(end)) type[seq_len(end)] <- "yaml"
  }
  for (i in seq_along(lines)) {
    if (type[[i]] == "yaml") next
    if (!in_chunk && grepl("^\\s*(```+|~~~+)\\s*\\{", lines[[i]])) {
      in_chunk <- TRUE
      fence <- sub("^\\s*(`+|~+).*", "\\1", lines[[i]])
      type[[i]] <- "fence"
    } else if (in_chunk && grepl(paste0("^\\s*", fence, "\\s*$"), lines[[i]])) {
      in_chunk <- FALSE
      type[[i]] <- "fence"
    } else if (in_chunk) {
      type[[i]] <- "code"
    }
  }
  type
}
doc_types <- lapply(doc_files, function(f) classify_doc(text[[f]]))
names(doc_types) <- doc_files

# --- Config keys ---------------------------------------------------------------------------

config_keys <- character()
top_keys <- character()
if (file.exists("config.yaml")) {
  cfg_lines <- read_lines("config.yaml")
  key_re <- "^(\\s*)([A-Za-z][A-Za-z0-9_]*)\\s*:"
  hit <- grepl(key_re, cfg_lines) & !grepl("^\\s*#", cfg_lines)
  keys <- sub(paste0(key_re, ".*$"), "\\2", cfg_lines[hit])
  indent <- nchar(sub(paste0(key_re, ".*$"), "\\1", cfg_lines[hit]))
  config_keys <- unique(keys)
  top_keys <- unique(keys[indent == 0])
}
# Keys of SPECIES_SETTINGS entries are stock names, not settings.
stock_names <- character()
if (requireNamespace("yaml", quietly = TRUE) && file.exists("config.yaml")) {
  cfg <- tryCatch(yaml::yaml.load(paste(cfg_lines, collapse = "\n")), error = function(e) NULL)
  if (is.null(cfg)) {
    add("ERROR", "config-parse", "config.yaml", NA, "config.yaml does not parse as YAML")
  } else {
    stock_names <- names(cfg$SPECIES_SETTINGS)
  }
}
setting_keys <- setdiff(config_keys, stock_names)
upper_keys <- setting_keys[grepl("^[A-Z][A-Z0-9_]*$", setting_keys)]

# 1. `$` partial matching on config lists. `cfg$NAME` with NAME absent but a prefix of a
#    present key silently returns the other key (REFERENCE_GEAR -> REFERENCE_GEAR_MODEL).
if (length(upper_keys)) {
  for (f in names(text)[grepl("\\.(R|r|qmd|Rmd)$", names(text))]) {
    lines <- text[[f]]
    # `$` access on a config-like list (cfg, config, settings, ...), not on data columns.
    access_re <- "(?i:[a-z_.0-9]*(cfg|config|conf|settings)[a-z_.0-9]*)(\\[\\[[^]]*\\]\\])?\\$[A-Z][A-Z0-9_]*\\b"
    m <- gregexpr(access_re, lines, perl = TRUE)
    for (i in which(vapply(m, function(x) x[[1]] > 0, logical(1)))) {
      if (grepl("^\\s*#", lines[[i]])) next
      names_used <- sub("^.*\\$", "", regmatches(lines[[i]], m[i])[[1]])
      for (nm in unique(names_used)) {
        longer <- upper_keys[startsWith(upper_keys, nm) & upper_keys != nm]
        if (!length(longer)) next
        if (!nm %in% upper_keys) {
          add("ERROR", "partial-match", f, i, sprintf(
            "`$%s` is not a config key but partially matches %s; use [[\"%s\", exact = TRUE]]",
            nm, paste(longer, collapse = ", "), nm))
        } else {
          add("INFO", "partial-match", f, i, sprintf(
            "`$%s` partially matches %s whenever %s is absent (e.g. removed in a species block); prefer [[\"%s\", exact = TRUE]] for optional keys",
            nm, paste(longer, collapse = ", "), nm, nm))
        }
      }
    }
  }
}

# 2. Config keys never read anywhere (dead keys) and UPPER_CASE names read but never defined.
if (length(top_keys)) {
  corpus <- paste(unlist(text[setdiff(names(text), "config.yaml")]), collapse = "\n")
  for (k in setdiff(setting_keys, "SPECIES_SETTINGS")) {
    if (!grepl(paste0("\\b", k, "\\b"), corpus, perl = TRUE)) {
      line <- which(grepl(paste0("^\\s*", k, "\\s*:"), cfg_lines))[1]
      add("WARN", "unused-config-key", "config.yaml", line,
          sprintf("%s is set but no R, qmd or shell file reads it", k))
    }
  }
  used <- unique(unlist(regmatches(corpus, gregexpr(
    "(?<=cfg\\$|cfg\\[\\[\")[A-Z][A-Z0-9_]+", corpus, perl = TRUE))))
  for (k in setdiff(used, setting_keys)) {
    add("INFO", "undefined-config-key", "(project)", NA, sprintf(
      "cfg$%s is read but not in config.yaml; check that a default is set and documented", k))
  }
}

# --- R code --------------------------------------------------------------------------------

# 3. Functions defined in R/ and never called anywhere else (dead code).
defs <- list()
for (f in r_files) {
  lines <- text[[f]]
  hit <- grep("^([A-Za-z.][A-Za-z0-9._]*)\\s*(<-|=)\\s*function\\b", lines)
  for (i in hit) {
    defs[[length(defs) + 1]] <- data.frame(
      name = sub("^([A-Za-z.][A-Za-z0-9._]*).*", "\\1", lines[[i]]), file = f, line = i,
      stringsAsFactors = FALSE)
  }
}
if (length(defs)) {
  defs <- do.call(rbind, defs)
  corpus_all <- unlist(text)
  for (j in seq_len(nrow(defs))) {
    nm <- defs$name[[j]]
    pattern <- paste0("(^|[^A-Za-z0-9._])", gsub(".", "\\.", nm, fixed = TRUE), "([^A-Za-z0-9._]|$)")
    n <- sum(grepl(pattern, corpus_all, perl = TRUE))
    if (n <= 1) add("WARN", "unused-function", defs$file[[j]], defs$line[[j]],
                    sprintf("%s() is defined but never used", nm))
  }
  dup <- defs[duplicated(defs$name) | duplicated(defs$name, fromLast = TRUE), ]
  for (nm in unique(dup$name)) {
    d <- dup[dup$name == nm, ]
    add("WARN", "duplicate-function", d$file[[1]], d$line[[1]], sprintf(
      "%s() is defined %d times (%s); the later definition wins when both are sourced",
      nm, nrow(d), paste0(d$file, ":", d$line, collapse = ", ")))
  }
}

# --- Quarto documents ----------------------------------------------------------------------

labels_all <- character()
refs <- list()
cites <- list()
for (f in doc_files) {
  lines <- text[[f]]
  type <- doc_types[[f]]

  # 4. Inline R with an odd number of quotes: a backtick inside the string ended the code early.
  m <- gregexpr("`r ([^`]*)`", lines)
  for (i in which(type == "prose" & vapply(m, function(x) x[[1]] > 0, logical(1)))) {
    for (seg in regmatches(lines[[i]], m[i])[[1]]) {
      body <- sub("^`r ", "", sub("`$", "", seg))
      body <- gsub("\\\\\"", "", body)
      if (lengths(regmatches(body, gregexpr("\"", body))) %% 2 == 1) {
        add("ERROR", "inline-r-backtick", f, i,
            "inline R has unbalanced quotes; a backtick inside an inline R string ends the code early")
      }
    }
  }

  # 5. Captions that YAML reads as a list or that start with a bracket break cross-references.
  for (i in grep("^\\s*#\\|\\s*(fig|tbl)-cap:\\s*\\[", lines)) {
    add("ERROR", "bracket-caption", f, i,
        "caption starts with '[': YAML reads it as a list and the cross-reference fails silently; quote it")
  }

  # 6. Duplicate chunk labels within a document.
  label_re <- "^\\s*(#|%%|//)\\|\\s*(lst-)?label:"
  lab <- c(sub(paste0(label_re, "\\s*\"?([^\" ]+)\"?.*"), "\\3", lines[grepl(label_re, lines)]),
           sub("^\\s*```+\\s*\\{r[ ,]+([A-Za-z0-9_-]+).*", "\\1",
               lines[grepl("^\\s*```+\\s*\\{r[ ,]+[A-Za-z0-9_-]+\\s*[,}]", lines) &
                       !grepl("\\{r[ ,]+[A-Za-z0-9_-]+\\s*=", lines)]))
  for (d in unique(lab[duplicated(lab)])) {
    add("ERROR", "duplicate-label", f, which(grepl(paste0("label:\\s*\"?", d, "\\b"), lines))[1],
        sprintf("chunk label %s is used more than once", d))
  }
  labels_all <- c(labels_all, lab,
                  unlist(regmatches(lines, gregexpr("(?<=\\{#)(fig|tbl|sec|eq|lst)-[A-Za-z0-9_-]+",
                                                    lines, perl = TRUE))))

  # Cross-references and citations (checked after all labels are known).
  for (i in which(type == "prose")) {
    r <- regmatches(lines[[i]], gregexpr("(?<![A-Za-z0-9.])@(fig|tbl|sec|eq|lst)-[A-Za-z0-9_-]*[A-Za-z0-9]",
                                         lines[[i]], perl = TRUE))[[1]]
    if (length(r)) refs[[length(refs) + 1]] <- data.frame(file = f, line = i, ref = sub("^@", "", r))
    br <- regmatches(lines[[i]], gregexpr("\\[[^]]*@[^]]*\\]", lines[[i]]))[[1]]
    k <- unlist(regmatches(br, gregexpr("(?<=@)[A-Za-z0-9_:.-]*[A-Za-z0-9_]", br, perl = TRUE)))
    k <- k[!grepl("^(fig|tbl|sec|eq|lst)-", k)]
    if (length(k)) cites[[length(cites) + 1]] <- data.frame(file = f, line = i, key = k)
  }

  # 7. Unfilled placeholders and open markers.
  if (!template_mode) {
    for (i in grep("\\{\\{[^<{}][^}]*\\}\\}", lines)) {
      if (!grepl("\\{\\{<", lines[[i]])) add("ERROR", "placeholder", f, i, "unfilled {{...}} placeholder")
    }
  }
  for (i in which(type == "prose" & grepl("\\b(TODO|FIXME|XXX|TBD)\\b|\\(rerun\\)", lines))) {
    add("WARN", "open-marker", f, i, trimws(substr(lines[[i]], 1, 120)))
  }

  # 8. Numbers with units typed into prose. Most should come from config or outputs via inline R.
  for (i in which(type == "prose")) {
    prose <- gsub("`r [^`]*`", "", lines[[i]])
    prose <- gsub("\\[[^]]*@[^]]*\\]", "", prose)
    if (grepl("(?<![A-Za-z0-9.-])\\d+(\\.\\d+)?\\s?(%|km|cm|kt|tonnes|hauls|stations)\\b", prose, perl = TRUE) &&
        !grepl("^\\s*(#|\\||<!--|:::|!\\[)", prose)) {
      add("INFO", "hardcoded-number", f, i, trimws(substr(lines[[i]], 1, 140)))
    }
  }
}

if (length(refs)) {
  refs <- do.call(rbind, refs)
  for (j in which(!refs$ref %in% labels_all)) {
    add("ERROR", "missing-crossref", refs$file[[j]], refs$line[[j]],
        sprintf("@%s has no matching label in any document", refs$ref[[j]]))
  }
}

if (length(cites) && length(bib_files)) {
  bib_keys <- unlist(lapply(bib_files, function(b) {
    x <- read_lines(b)
    sub("^\\s*@[A-Za-z]+\\s*\\{\\s*([^,]+),.*", "\\1", x[grepl("^\\s*@[A-Za-z]+\\s*\\{", x)])
  }))
  cites <- do.call(rbind, cites)
  for (j in which(!cites$key %in% bib_keys & !duplicated(cites$key))) {
    add("WARN", "missing-citation", cites$file[[j]], cites$line[[j]],
        sprintf("[@%s] is not in %s (fine only if report_software() adds it at render)",
                cites$key[[j]], paste(basename(bib_files), collapse = ", ")))
  }
  dup_keys <- unique(bib_keys[duplicated(bib_keys)])
  for (k in dup_keys) add("WARN", "duplicate-bib-key", paste(bib_files, collapse = ", "), NA,
                           sprintf("bibliography key %s is defined more than once", k))
}

# --- Repository hygiene --------------------------------------------------------------------

# 9. Private paths and tracked data.
for (f in all_files[grepl("\\.(R|r|qmd|Rmd|sh|md|yml|yaml|json|txt)$", all_files)]) {
  lines <- if (!is.null(text[[f]])) text[[f]] else read_lines(f)
  for (i in grep("/Users/[A-Za-z]|[A-Z]:\\\\\\\\?Users|OneDrive|CloudStorage", lines)) {
    add(if (template_mode) "ERROR" else "WARN", "private-path", f, i,
        "absolute personal path; use here::here(), an environment variable or a config key")
  }
}
if (in_git) {
  data_ext <- "\\.(rds|rda|RData|csv|duckdb|gpkg|shp|parquet|xlsx|feather)$"
  tracked_data <- tracked[grepl(data_ext, tracked, ignore.case = TRUE) &
                            grepl("^(data/|ai/review/)", tracked) &
                            !grepl("^data/source/README", tracked)]
  for (f in tracked_data) add("WARN", "tracked-data", f, NA,
                              "data file is tracked by git; Biotic-derived records must stay local")
}

# 10. Rendered HTML next to its source: unresolved cross-references, leaked errors or missing
#     values, and renders older than their source or config.yaml.
html_files <- list.files(".", pattern = "\\.html$", recursive = TRUE)
html_files <- html_files[!grepl(skip_dirs, html_files) & !grepl("^(renv|_site|site)/", html_files)]
for (h in html_files) {
  src <- sub("\\.html$", ".qmd", h)
  if (!file.exists(src)) next
  x <- read_lines(h)
  x <- gsub("<script.*?</script>", "", x, perl = TRUE)
  # Prose paragraphs and captions only, tags stripped (tables and code legitimately hold NA).
  prose_i <- grep("<p>|<figcaption|<caption", x)
  prose <- gsub("<[^>]+>", " ", x[prose_i])
  checks <- list(
    list("unresolved cross-reference (?@...)", "\\?@(fig|tbl|sec|eq|lst)-", seq_along(x), x, "ERROR"),
    list("R error printed in output", "^\\s*(##\\s*)?Error( in |:)", seq_along(x), gsub("<[^>]+>", "", x), "ERROR"),
    list("R value NA/NaN/NULL/Inf/character(0) printed in prose",
         "(?<![A-Za-z0-9_])(NA|NaN|NULL|-?Inf|character\\(0\\)|numeric\\(0\\))(?![A-Za-z0-9_(])",
         prose_i, prose, "WARN")
  )
  for (ck in checks) {
    i <- ck[[3]][grepl(ck[[2]], ck[[4]], perl = TRUE)]
    if (length(i)) add(ck[[5]], "rendered-html", h, i[[1]], sprintf("%s (%d lines)", ck[[1]], length(i)))
  }
  newer <- c(src, "config.yaml")[file.mtime(c(src, "config.yaml")) > file.mtime(h)]
  newer <- newer[!is.na(newer)]
  if (length(newer)) add("INFO", "stale-render", h, NA,
                         sprintf("older than %s; re-render before citing its numbers", paste(newer, collapse = " and ")))
}

# --- Report --------------------------------------------------------------------------------

if (!length(findings)) {
  cat("No findings.\n")
  quit(status = 0)
}
out <- do.call(rbind, findings)
out <- out[order(match(out$severity, c("ERROR", "WARN", "INFO")), out$check, out$where), ]
out <- out[!duplicated(out[c("check", "where", "message")]), ]
writeLines(paste(out$severity, out$check, out$where, out$message, sep = "\t"))
cat(sprintf("\n%d ERROR, %d WARN, %d INFO\n", sum(out$severity == "ERROR"),
            sum(out$severity == "WARN"), sum(out$severity == "INFO")))
quit(status = if (any(out$severity == "ERROR")) 1 else 0)
