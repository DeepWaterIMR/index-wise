# docs/render.R — render all model documents and refresh outputs end-to-end.
#
# This is a FULL rebuild and is SLOW. The same discipline as index-render applies:
#   1. Code-review changed chunks before running.
#   2. Prefer running individual documents in a screen session with a log in logs/
#      (see the index-render skill) rather than this whole script interactively.
#   3. After the first successful build, flip the compute toggles in each qmd to FALSE so
#      re-renders load cached objects from data/output/ instead of refitting.
#
# Usage (from the project root):
#   Rscript docs/render.R            # render everything
#   Rscript docs/render.R data       # render only the data documents
#   Rscript docs/render.R fit        # etc.
#   Rscript docs/render.R cpue       # the commercial CPUE document (also in "all" when its
#                                    # logbook extract, config CPUE: file, exists)

args  <- commandArgs(trailingOnly = TRUE)
stage <- if (length(args)) args[[1]] else "all"

if (!requireNamespace("quarto", quietly = TRUE))
  stop("The 'quarto' package is required: install.packages('quarto')")
if (!requireNamespace("yaml", quietly = TRUE))
  stop("The 'yaml' package is required: install.packages('yaml')")

# Read as UTF-8 bytes so Norwegian species names (å/æ/ø) parse regardless of R locale.
cfg_txt <- readChar("config.yaml", file.info("config.yaml")$size, useBytes = TRUE)
Encoding(cfg_txt) <- "UTF-8"
cfg  <- yaml::yaml.load(cfg_txt, eval.expr = FALSE)
# Stocks: the SPECIES_SETTINGS keys, or the single stock (STOCK_SLUG, else SPECIES_SLUG).
stocks <- if (!is.null(cfg$SPECIES_SETTINGS)) names(cfg$SPECIES_SETTINGS) else
  (if (!is.null(cfg$STOCK_SLUG)) cfg$STOCK_SLUG else cfg$SPECIES_SLUG)
if (length(args) > 1) stocks <- intersect(args[-1], stocks)
# Root of the document folders: "docs", or e.g. "docs/benchmark" (config DOCS_DIR).
docs_dir <- if (!is.null(cfg$DOCS_DIR)) cfg$DOCS_DIR else "docs"

dir.create("logs", showWarnings = FALSE)

render <- function(path) {
  if (!file.exists(path)) { message("skip (missing): ", path); return(invisible()) }
  message("Rendering: ", path)
  quarto::quarto_render(path)
}

# Usage: Rscript docs/render.R <stage> [stock ...]
# Order of the documents (each reads what the earlier ones wrote; knowledge/pipeline.md):
#   data      <stock>-2-survey-selection (compiles the data; machine with the Biotic database),
#             <stock>-3-data, <stock>-0-background
#   fit       <stock>-4-fit (base fit and prediction grid used by the selection)
#   validate  <stock>-5-validate (reads the selection caches of R/validation or R/hpc/slurm)
#   report    <stock>-6-report (reads the caches of R/report/run_report.sh)
#   summary   <stock>-1-summary (reads the report caches, so it comes last)
#   cpue      the optional commercial CPUE document
# The selection and the report computations are not run here: run them on the server first
# (R/run_models.sh runs fit to summary unattended).
run_stage <- function(st) stage %in% c("all", st)
for (k in stocks) {
  if (run_stage("data")) {
    for (part in c("2-survey-selection", "3-data"))
      render(file.path(docs_dir, "data", paste0(k, "-", part, ".qmd")))
    render(file.path(docs_dir, "background", paste0(k, "-0-background.qmd")))
  }
  if (run_stage("fit"))      render(file.path(docs_dir, "sdmtmb", "fit", paste0(k, "-4-fit.qmd")))
  if (run_stage("validate")) render(file.path(docs_dir, "sdmtmb", "validation", paste0(k, "-5-validate.qmd")))
  if (run_stage("report"))   render(file.path(docs_dir, "sdmtmb", k, paste0(k, "-6-report.qmd")))
  if (run_stage("summary"))  render(file.path(docs_dir, "data", paste0(k, "-1-summary.qmd")))
}
cpue_file <- cfg$CPUE$file
if (identical(stage, "cpue") || (identical(stage, "all") && !is.null(cpue_file) && file.exists(cpue_file)))
  render(file.path(docs_dir, "sdmtmb", "cpue", "cpue.qmd"))

message("Done: ", stage)
