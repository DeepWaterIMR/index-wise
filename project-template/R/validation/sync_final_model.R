# Write the model selection's decisions into config.yaml (FINAL_MODEL, MESH_CUTOFF_KM, the
# smoothed-index structure and GRID_KM of one stock), so that the report follows the selection
# without a hand-copied specification (knowledge/pipeline.md, step 8).
#   Rscript R/validation/sync_final_model.R <stock>
# Reads data/output/<stock>/selection/{decisions.rds, stage-grid.rds}. In a multi-stock config
# the values go into the stock's SPECIES_SETTINGS block, otherwise at the top level. Only the
# value of an existing setting line is replaced (comments and layout are kept); missing settings
# are added. Every change is printed, and the script ends with "SYNC DONE". Decisions the
# report cannot apply (barrier mesh, separate positive-component terms, no year factor) are
# reported and left out.
args <- commandArgs(trailingOnly = TRUE)
index_species <- args[[1]]
suppressMessages(source(here::here("R", "0_setup.R")))
source(here::here("R", "validation", "sync_lib.R"))

sel_dir <- file.path(here::here(cfg$OUTPUT_DIR), "selection")
d <- readRDS(file.path(sel_dir, "decisions.rds"))
set <- cfg$SELECTION %||% list()

# Grid: the coarsest grid whose index stays within GRID_TOL of the finest grid's index (terminal
# year, mean of the last WINDOW years, MARD), the rule of the validate document; the current
# GRID_KM is kept while it passes.
grid_km <- NULL
gf <- file.path(sel_dir, "stage-grid.rds")
if (file.exists(gf)) {
  grid_km <- grid_decision(readRDS(gf)$index, current = cfg$GRID_KM,
                           tol = as.numeric(set$GRID_TOL %||% 0.01),
                           window = as.integer(set$WINDOW %||% 5L))
}

lock <- here::here("config.yaml.lock")
# A lock older than 10 minutes was left by a killed run: the edit itself takes seconds.
while (!dir.create(lock, showWarnings = FALSE)) {
  age <- difftime(Sys.time(), file.mtime(lock), units = "mins")
  if (!is.na(age) && age > 10) unlink(lock, recursive = TRUE) else Sys.sleep(2)
}
on.exit(unlink(lock, recursive = TRUE), add = TRUE)
path <- here::here("config.yaml")
res <- sync_config_lines(readLines(path, encoding = "UTF-8"), index_species, d, grid_km)
writeLines(res$lines, path, useBytes = TRUE)

cat("Stock:", index_species, "\n")
cat("Decisions:", paste(names(res$new), unlist(res$new), sep = " = ", collapse = "; "), "\n")
cat(if (length(res$changes)) paste("CHANGED:", res$changes, collapse = "\n") else
  "config.yaml already matches the selection", "\n")
if (length(res$problems)) cat(paste("NOT APPLIED:", res$problems, collapse = "\n"), "\n")
cat("SYNC DONE\n")
