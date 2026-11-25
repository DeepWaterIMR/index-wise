# Combine a stage's cached candidates: phase "fit" writes the CV shortlist, phase "final"
# applies the decision rule. Stage "grid" computes the grid-resolution comparison.
#   Rscript R/validation/assemble_stage.R <species> <stage> <fit|final|names>
a <- commandArgs(trailingOnly = TRUE)
source(here::here("R", "validation", "stage_lib.R"))
if (a[3] == "names") {
  s <- stage_setup(a[1])
  cat(if (a[2] == "mesh") mesh_ladder(s$cfg) else names(stage_candidates(a[2], s, read_decisions(s))), sep = "\n")
} else if (a[2] == "mesh") {
  assemble_mesh(a[1])
} else if (a[2] == "grid") {
  run_grid_stage(a[1])
} else {
  assemble_stage(a[1], a[2], a[3])
}
cat("ASSEMBLE DONE\n")
