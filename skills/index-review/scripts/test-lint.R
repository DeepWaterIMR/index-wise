#!/usr/bin/env Rscript
# test-lint.R — plants one defect per check in a synthetic project and asserts that
# lint_project.R reports each of them. Run from anywhere: Rscript test-lint.R

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
script_dir <- dirname(normalizePath(gsub("~+~", " ", script_arg, fixed = TRUE)))  # Rscript encodes spaces
lint <- file.path(script_dir, "lint_project.R")

fx <- file.path(tempfile("index-review-fixture-"))
dir.create(file.path(fx, "docs"), recursive = TRUE)
writeLines(c('REFERENCE_GEAR_MODEL: "x"', "GRID_KM: 20", "OLD_KEY: 1"), file.path(fx, "config.yaml"))
writeLines(c(
  "---", "title: t", "---",
  "See @fig-missing and [@nokey]. The grid is 20 km.",
  "",
  'Value `r paste0("a `b`", 1)` here.',
  "",
  "```{r}", "#| label: dup", "#| fig-cap: [bad] caption", "g <- cfg$REFERENCE_GEAR + cfg$GRID_KM", "```",
  "",
  "```{r}", "#| label: dup", "```"
), file.path(fx, "docs", "a.qmd"))
writeLines(c("@article{key1,", " title={x}}"), file.path(fx, "docs", "refs.bib"))
writeLines(c("<p>The index fell by NA % and see ?@fig-missing.</p>", "<pre>Error in foo: bar</pre>"),
           file.path(fx, "docs", "a.html"))
writeLines("unused_fn <- function() 1", file.path(fx, "helpers.R"))

out <- suppressWarnings(system2("Rscript", c(shQuote(lint), shQuote(fx)), stdout = TRUE, stderr = TRUE))
expected <- c("partial-match", "inline-r-backtick", "bracket-caption", "duplicate-label",
              "missing-crossref", "missing-citation", "unused-config-key", "unused-function",
              "hardcoded-number", "rendered-html")
missing <- expected[!vapply(expected, function(k) any(grepl(paste0("\t", k, "\t"), out)), logical(1))]
false_pos <- grep("unused-config-key\tconfig.yaml:2", out, value = TRUE)  # GRID_KM is read

unlink(fx, recursive = TRUE)
if (length(missing) || length(false_pos)) {
  writeLines(out)
  stop("lint_project.R missed: ", paste(missing, collapse = ", "),
       if (length(false_pos)) " | false positive on GRID_KM" else "")
}
cat("test-lint: all", length(expected), "planted defects reported\n")
