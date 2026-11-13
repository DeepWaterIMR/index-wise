# Synthetic contract checks. Run from the index-wise repository root.
# Optional --render verifies a lightweight report, never the survey/model pipeline.
source("scaffold.R")

# Rscript can run under the C locale, where yaml::read_yaml()/write_yaml() and readLines()
# mangle the non-ASCII names in the fixtures. Read YAML with scaffold.R's .read_yaml_utf8(),
# write UTF-8 bytes back, and mark text read from generated files as UTF-8.
write_yaml_utf8 <- function(x, path) {
  writeBin(charToRaw(enc2utf8(yaml::as.yaml(x))), path)
}
workspace <- Sys.getenv("INDEX_TEMPLATE_TEST_DIR", unset = tempfile("index-scaffold-"))
dir.create(workspace)
# Test the canonical config and legacy fallback under an isolated temporary home.
old_home <- Sys.getenv("HOME", unset = NA_character_)
Sys.setenv(HOME = workspace)
canonical_root <- file.path(workspace, "canonical-install")
legacy_root <- file.path(workspace, "legacy-install")
dir.create(file.path(canonical_root, "project-template"), recursive = TRUE)
dir.create(file.path(legacy_root, "project-template"), recursive = TRUE)
dir.create(file.path(workspace, ".index-wise"))
dir.create(file.path(workspace, ".index-template"))
jsonlite::write_json(list(index_template_path = canonical_root),
                     file.path(workspace, ".index-wise", "config.json"), auto_unbox = TRUE)
jsonlite::write_json(list(index_template_path = legacy_root),
                     file.path(workspace, ".index-template", "config.json"), auto_unbox = TRUE)
stopifnot(normalizePath(.find_template()) == normalizePath(file.path(canonical_root, "project-template")))
# A stale canonical path must not mask a valid legacy install.
jsonlite::write_json(list(index_template_path = file.path(workspace, "missing-install")),
                     file.path(workspace, ".index-wise", "config.json"), auto_unbox = TRUE)
stopifnot(normalizePath(.find_template()) == normalizePath(file.path(legacy_root, "project-template")))
unlink(c(file.path(workspace, ".index-wise", "config.json"),
         file.path(workspace, ".index-template", "config.json")))
stopifnot(normalizePath(.find_template()) == normalizePath("project-template"))
if (is.na(old_home)) Sys.unsetenv("HOME") else Sys.setenv(HOME = old_home)
cfg <- .read_yaml_utf8("examples/redfish/config.yaml")   # locale-independent (scaffold.R)
cfg$AUTHORS <- list(list(name = "Test: \u00c5uthor \"One\"", affiliation = "test"),
                    list(name = "Second Author", affiliation = c("test", "other")))
cfg$AFFILIATIONS <- list(list(id = "test", name = "Synthetic Institute"),
                         list(id = "other", name = "Other Institute"))
config_file <- file.path(workspace, "config.yaml")
write_yaml_utf8(cfg, config_file)
# With no saved config, scaffold_index() must still source the template in the current repo.
Sys.setenv(HOME = workspace)
scaffold_index(config_file, file.path(workspace, "default-template-project"), dry = TRUE)
if (is.na(old_home)) Sys.unsetenv("HOME") else Sys.setenv(HOME = old_home)
target <- file.path(workspace, "project")
# The redfish example names an ASSESSMENT_MODEL, so the default layout nests the document
# folders under docs/benchmark (DOCS_DIR); a flat docs/ layout is checked further down.
scaffold_index(config_file, target, template = "project-template")
docs_root <- "docs/benchmark"
shared_setup <- file.path(dirname(normalizePath(".")), "wise-writing",
                          "project-template", "R", "package_setup.R")
copied_setup <- file.path(target, "R", "package_setup.R")
stopifnot(file.exists(copied_setup),
          identical(readBin(copied_setup, "raw", n = file.info(copied_setup)$size),
                    readBin(shared_setup, "raw", n = file.info(shared_setup)$size)))
setup_text <- readLines(file.path(target, "R", "0_setup.R"), warn = FALSE)
stopifnot(any(grepl('"R", "package_setup.R"', setup_text, fixed = TRUE)),
          any(grepl('unset = "false"', setup_text, fixed = TRUE)),
          any(grepl('R_INDEX_INSTALL_MISSING=true', setup_text, fixed = TRUE)),
          !any(grepl("install.packages(", setup_text, fixed = TRUE)))
stopifnot(all(dir.exists(file.path(target, c("ai/memory", "ai/tests", "ai/review",
  "R", file.path(docs_root, c("assets", "background", "data", "sdmtmb")), "figures", "config",
  "logs")))))
stopifnot(.read_yaml_utf8(file.path(target, "config.yaml"))$DOCS_DIR == docs_root,
          file.exists(file.path(target, "docs", "render.R")),
          !any(dir.exists(file.path(target, "docs", c("assets", "background", "data", "sdmtmb")))))
stopifnot(!any(file.exists(file.path(target, c("memory", "review", "R/00_setup.R")))))
stopifnot(file.exists(file.path(target, ".here")),
          .read_yaml_utf8(file.path(target, "VERSION"))$version == "0.1.0")
qmds <- list.files(file.path(target, "docs"), "\\.qmd$", recursive = TRUE, full.names = TRUE)
main <- qmds[!grepl("-section.qmd$", qmds)]
stopifnot(length(main) == 8L)   # three data documents, fishable length, fit, validate, report, CPUE
for (path in qmds) {
  text <- readLines(path, warn = FALSE, encoding = "UTF-8")
  stopifnot(!any(grepl("\\{\\{(SPECIES|REGION|AUTHORS|AFFILIATIONS)", text)))
  # Parse every R chunk without evaluating analysis or installing packages.
  in_r <- FALSE
  code <- character()
  for (line in text) {
    if (grepl("^```\\{r", line)) {
      in_r <- TRUE
      code <- character()
    } else if (in_r && grepl("^```", line)) {
      parse(text = code)
      option_lines <- grep("^#\\| ", code, value = TRUE)
      option_keys <- sub("^#\\| ([^:]+):.*$", "\\1", option_lines)
      option_keys <- option_keys[grepl(":", option_lines)]
      stopifnot(!anyDuplicated(option_keys))
      in_r <- FALSE
    } else if (in_r) code <- c(code, line)
  }
  stopifnot(!in_r)
  if (!path %in% main) next
  ends <- which(text == "---")
  header <- yaml::yaml.load(paste(text[(ends[1] + 1):(ends[2] - 1)], collapse = "\n"), eval.expr = FALSE)
  stopifnot(header$author[[1]]$name == cfg$AUTHORS[[1]]$name,
            header$affiliations[[1]]$id == "test",
            header$author[[1]]$affiliations[[1]]$ref == "test",
            length(header$author[[2]]$affiliations) == 2L,
            header$format$html$`toc-title` == header$title,
            isTRUE(header$format$html$`code-fold`),
            header$format$html$`code-summary` == "Show code",
            !identical(header$execute$echo, FALSE),
            header$execute$`fig-width` == 6.69,
            header$`published-title` == "Version",
            file.exists(file.path(dirname(path), header$csl)),
            any(text == "# References {.unnumbered}"),
            which(text == "# References {.unnumbered}") <
              which(text == "# Appendix: analysis scripts {.appendix}"))
}
for (path in list.files(file.path(target, "R"), "\\.R$", full.names = TRUE)) parse(path)
invisible(parse(file.path(target, "docs/render.R")))
# Flat layout: docs_dir = "docs" overrides the assessment default.
flat <- file.path(workspace, "project-flat")
scaffold_index(config_file, flat, template = "project-template", docs_dir = "docs")
stopifnot(all(dir.exists(file.path(flat, "docs", c("assets", "background", "data", "sdmtmb")))),
          !dir.exists(file.path(flat, "docs", "benchmark")),
          .read_yaml_utf8(file.path(flat, "config.yaml"))$DOCS_DIR == "docs",
          length(list.files(file.path(flat, "docs"), "\\.qmd$", recursive = TRUE)) == length(qmds),
          !any(grepl("\\{\\{(SPECIES|REGION|STOCK|AREA|AUTHORS|AFFILIATIONS)", unlist(lapply(list.files(flat, "\\.(qmd|R|yml|yaml)$", recursive = TRUE,
            full.names = TRUE), readLines, warn = FALSE, encoding = "UTF-8")))))
# Bad metadata must fail before creating a destination, including in dry-run mode.
cfg$AUTHORS[[1]]$affiliation <- "missing"
write_yaml_utf8(cfg, config_file)
bad <- try(scaffold_index(config_file, file.path(workspace, "invalid"),
                          template = "project-template"), silent = TRUE)
stopifnot(inherits(bad, "try-error"), !dir.exists(file.path(workspace, "invalid")))
source("project-template/R/report_helpers.R")
bib <- file.path(workspace, "software.bib")
prose <- capture.output(report_software("knitr", bib))
stopifnot(any(grepl("@software-base-1", prose, fixed = TRUE)),
          any(grepl("@Manual{software-base-1,", readLines(bib), fixed = TRUE)))
if ("--render" %in% commandArgs(TRUE)) {
  path <- main[grepl("/fit/fit.qmd$", main)]
  original <- readLines(path)
  header_end <- which(original == "---")[2]
  fixture <- c(original[seq_len(header_end)], "", "# Purpose", "",
    "Synthetic report for checking metadata, code folding, citations, and project-root paths.",
    "", "```{r}", "#| label: tbl-check", '#| tbl-cap: "Synthetic values used for the layout check."',
    'knitr::kable(data.frame(value = 1:3))', "```", "",
    "The fixture contained three values (@tbl-check).", "", "# Software and reproducibility", "",
    "```{r}", "#| results: asis", 'source(here::here("R", "report_helpers.R"))',
    'report_software("knitr", here::here(cfg$DOCS_DIR %||% "docs", "assets", "fit-software.bib"))', "```", "",
    "# References {.unnumbered}", "", "::: {#refs}", ":::")
  writeLines(fixture, path)
  status <- system2("quarto", c("render", shQuote(path), "--to", "html"))
  stopifnot(status == 0L)
  html <- readLines(sub("qmd$", "html", path), warn = FALSE)
  stopifnot(any(grepl("Show code", html, fixed = TRUE)),
            any(grepl("Version", html, fixed = TRUE)),
            any(grepl('id="ref-software-base-1"', html, fixed = TRUE)),
            !any(grepl('class="citation"[^>]*>.*\\[@', html)))
}
cat("Scaffold contract checks passed. Synthetic project:", target, "\n")
