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
slug <- cfg$SPECIES_SLUG
stock <- if (!is.null(cfg$STOCK_SLUG)) cfg$STOCK_SLUG else slug
# Root of the document folders: "docs", or e.g. "docs/benchmark" (config DOCS_DIR).
docs_dir <- if (!is.null(cfg$DOCS_DIR)) cfg$DOCS_DIR else "docs"

dir.create("logs", showWarnings = FALSE)

render <- function(path) {
  if (!file.exists(path)) { message("skip (missing): ", path); return(invisible()) }
  message("Rendering: ", path)
  quarto::quarto_render(path)
}

if (stage %in% c("all", "data")) {
  for (part in c("2-survey-selection", "3-data", "1-summary"))
    render(file.path(docs_dir, "data", paste0(stock, "-", part, ".qmd")))
}
if (stage %in% c("all", "fit"))      render(file.path(docs_dir, "sdmtmb", "fit", "fit.qmd"))
if (stage %in% c("all", "validate")) render(file.path(docs_dir, "sdmtmb", "validation", "validate.qmd"))
if (stage %in% c("all", "report"))   render(file.path(docs_dir, "sdmtmb", slug, "report.qmd"))
cpue_file <- cfg$CPUE$file
if (identical(stage, "cpue") || (identical(stage, "all") && !is.null(cpue_file) && file.exists(cpue_file)))
  render(file.path(docs_dir, "sdmtmb", "cpue", "cpue.qmd"))

message("Done: ", stage)
