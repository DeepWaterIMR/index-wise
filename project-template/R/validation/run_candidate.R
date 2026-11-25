# Fit (phase "fit") or cross-validate (phase "cv") one candidate of one selection stage.
#   Rscript R/validation/run_candidate.R <species> <stage> "<candidate>" <fit|cv> [n_workers]
a <- commandArgs(trailingOnly = TRUE)
source(here::here("R", "validation", "stage_lib.R"))
run_candidate(a[1], a[2], a[3], a[4], n_workers = if (length(a) > 4) as.integer(a[5]) else 10L)
cat("CANDIDATE DONE\n")
