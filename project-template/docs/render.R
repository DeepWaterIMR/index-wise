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

args  <- commandArgs(trailingOnly = TRUE)
stage <- if (length(args)) args[[1]] else "all"

if (!requireNamespace("quarto", quietly = TRUE))
  stop("The 'quarto' package is required: install.packages('quarto')")
if (!requireNamespace("yaml", quietly = TRUE))
  stop("The 'yaml' package is required: install.packages('yaml')")

cfg  <- yaml::read_yaml("config.yaml", eval.expr = FALSE)
slug <- cfg$SPECIES_SLUG
stock <- if (!is.null(cfg$STOCK_SLUG)) cfg$STOCK_SLUG else slug

dir.create("logs", showWarnings = FALSE)

render <- function(path) {
  if (!file.exists(path)) { message("skip (missing): ", path); return(invisible()) }
  message("Rendering: ", path)
  quarto::quarto_render(path)
}

if (stage %in% c("all", "data")) {
  for (part in c("2-survey-selection", "3-data", "1-summary"))
    render(file.path("docs/data", paste0(stock, "-", part, ".qmd")))
}
if (stage %in% c("all", "fit"))      render("docs/data-report/fit/fit.qmd")
if (stage %in% c("all", "validate")) render("docs/data-report/validation/validate.qmd")
if (stage %in% c("all", "report"))   render(file.path("docs", "data-report", slug, "report.qmd"))

message("Done: ", stage)
