# test-stock-parity.R — the numbered documents of every stock must be identical apart from the
# stock. The first stock in config.yaml (SPECIES_SETTINGS) is the master; edit its documents,
# then rewrite the others from them. Everything else that differs between the stocks belongs
# in config.yaml.
#
# Run from the project root before rendering or committing:
#   Rscript ai/tests/test-stock-parity.R          # check
#   Rscript ai/tests/test-stock-parity.R write    # rewrite every other stock's documents
# Allowed differences: the stock name in the YAML title lines (title, subtitle, toc-title,
# pagetitle), the `index_species` value and the `%||% "<name>"` fallback of the species name.
# A project with one stock passes trivially.

`%||%` <- function(a, b) if (is.null(a)) b else a
read_utf8 <- function(f) {
  x <- readLines(f, warn = FALSE, encoding = "UTF-8")
  Encoding(x) <- "UTF-8"
  x
}
cfg <- yaml::yaml.load(paste(read_utf8("config.yaml"), collapse = "\n"))
stocks <- cfg$SPECIES_SETTINGS
if (length(stocks) < 2) {
  cat("PASS   one stock: nothing to compare\n")
  quit(status = 0)
}
keys <- names(stocks)
name_of <- function(k) stocks[[k]]$SPECIES_NAME %||% cfg$SPECIES_NAME %||% k
docs <- cfg$DOCS_DIR %||% "docs"
master <- keys[1]

# The master's text with another stock's identity.
to_stock <- function(x, k) {
  from_name <- name_of(master)
  to_name <- name_of(k)
  title <- grepl("^\\s*(title|subtitle|toc-title|pagetitle):", x)
  x[title] <- gsub(from_name, to_name, x[title], fixed = TRUE, useBytes = TRUE)
  x <- gsub(paste0('index_species <- "', master, '"'), paste0('index_species <- "', k, '"'),
            x, fixed = TRUE, useBytes = TRUE)
  x <- gsub(paste0('%||% "', from_name, '"'), paste0('%||% "', to_name, '"'), x, fixed = TRUE, useBytes = TRUE)
  Encoding(x) <- "UTF-8"   # useBytes leaves the encoding "unknown"; the bytes are UTF-8
  x
}
# The twin path: <master>- file prefix and <master>/ folder replaced by the stock key.
twin_path <- function(f, k) {
  rel <- sub(paste0("^", docs, "/"), "", f)
  # Twice: in "<master>/<master>-6" the first match consumes the slash the second needs.
  for (pass in 1:2) rel <- sub(paste0("(^|/)", master, "(-|/)"), paste0("\\1", k, "\\2"), rel)
  file.path(docs, rel)
}

write <- identical(commandArgs(trailingOnly = TRUE)[1], "write")
masters <- list.files(docs, pattern = paste0("^", master, "-.*\\.qmd$"), recursive = TRUE, full.names = TRUE)
if (!length(masters)) stop("No documents of the master stock '", master, "' under ", docs)
fail <- FALSE
for (k in keys[-1]) for (f in masters) {
  twin <- twin_path(f, k)
  expected <- to_stock(read_utf8(f), k)
  if (write) {
    dir.create(dirname(twin), recursive = TRUE, showWarnings = FALSE)
    writeLines(enc2utf8(expected), twin, useBytes = TRUE)
    cat(sprintf("%-6s %s\n", "WROTE", twin))
    next
  }
  if (!file.exists(twin)) {
    cat(sprintf("%-6s %s (missing)\n", "FAIL", twin)); fail <- TRUE; next
  }
  actual <- read_utf8(twin)
  same <- length(actual) == length(expected) &&
    all(mapply(function(a, b) identical(charToRaw(enc2utf8(a)), charToRaw(enc2utf8(b))), actual, expected))
  if (same) {
    cat(sprintf("%-6s %s\n", "PASS", twin))
  } else {
    n <- min(length(actual), length(expected))
    first <- which(actual[seq_len(n)] != expected[seq_len(n)])[1] %||% (n + 1)
    cat(sprintf("%-6s %s (differs from %s at line %d)\n", "FAIL", twin, f, first)); fail <- TRUE
  }
}
if (fail) quit(status = 1)
