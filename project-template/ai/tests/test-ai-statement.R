# test-ai-statement.R — every document in docs/ must carry an AI statement.
#
# Run from the project root before rendering or committing:
#   Rscript ai/tests/test-ai-statement.R
# A document passes when it states the use of generative AI (the standard wording from
# wise-writing's ai-disclosure.md: "created with researcher-supervised generative AI") and
# names the model (no unfilled "<confirmed AI models>" placeholder). Child files included
# into another document ({{< include ... >}} or knitr child) are covered by their parent.
#
# In the index-wise project template itself, pass template = TRUE (the placeholder is
# expected there): Rscript ai/tests/test-ai-statement.R template

template <- identical(commandArgs(trailingOnly = TRUE)[1], "template")
docs <- list.files("docs", pattern = "\\.(qmd|Rmd)$", recursive = TRUE, full.names = TRUE)
text <- lapply(docs, readLines, warn = FALSE, encoding = "UTF-8")
names(text) <- docs
included <- unique(unlist(lapply(docs, function(f) {
  inc <- regmatches(text[[f]], regexpr("(?<=include )[^ >]+\\.(qmd|Rmd)|(?<=child = \")[^\"]+",
                                       text[[f]], perl = TRUE))
  if (length(inc)) normalizePath(file.path(dirname(f), inc), mustWork = FALSE)
})))
docs <- docs[!normalizePath(docs, mustWork = FALSE) %in% included]
docs <- docs[!grepl("^_", basename(docs))]   # partials such as _child.qmd

status <- vapply(docs, function(f) {
  x <- text[[f]]
  if (!any(grepl("generative AI", x, ignore.case = TRUE))) return("FAIL (no AI statement)")
  if (!template && any(grepl("<confirmed AI models>", x, fixed = TRUE)))
    return("FAIL (model not named: <confirmed AI models>)")
  "PASS"
}, character(1))
for (f in docs) cat(status[[f]], "-", f, "\n")
if (any(status != "PASS")) {
  stop("Documents without a complete AI statement: ",
       paste(docs[status != "PASS"], collapse = ", "), call. = FALSE)
}
