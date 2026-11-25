# Smoke test of the stage runner on a small subset (2 500 hauls, 150 km mesh, temporary cache):
# the first two candidates of every stage are fitted, two field candidates are cross-validated,
# and the field decision rule is applied. Run on the server (or a cluster devel queue) before a
# long selection, and on any new machine:
#   SMOKE=1 Rscript R/validation/smoke_test.R <stock>
# Include the optional candidates that may fail on a new machine (barrier mesh: sdmTMBextra and
# a cached land polygon) by listing them in SMOKE_EXTRA, e.g. SMOKE_EXTRA="Barrier mesh".
if (!nzchar(Sys.getenv("SMOKE"))) stop("Run with SMOKE=1, which uses a subset and a temporary cache.")
a <- commandArgs(trailingOnly = TRUE)
source(here::here("R", "validation", "stage_lib.R"))
sp <- a[1]
s <- stage_setup(sp)
d <- read_decisions(s)
extra <- strsplit(Sys.getenv("SMOKE_EXTRA"), ",")[[1]]
ok <- TRUE
for (st in c("fields", "geometry", "fixed", "family")) {
  nm <- names(stage_candidates(st, s, d))
  cat("==", st, ":", paste(nm, collapse = " | "), "\n")
  for (x in unique(c(head(nm, 2), intersect(trimws(extra), nm)))) {
    r <- try(run_candidate(sp, st, x, "fit", 1))
    cat(st, "|", x, "|", if (inherits(r, "try-error")) "FIT ERROR" else "fit ok", "\n")
    ok <- ok && !inherits(r, "try-error")
  }
}
two <- head(names(stage_candidates("fields", s, d)), 2)
for (x in two) {
  r <- try(run_candidate(sp, "fields", x, "cv", 2))
  cat("cv |", x, "|", if (inherits(r, "try-error")) "ERROR" else "ok", "\n")
  ok <- ok && !inherits(r, "try-error")
}
res <- try({
  st <- read_stage(s, "fields", two)
  stc <- read_stage(s, "fields", two, with_cv = TRUE)
  cvp <- cv_paired(list(cv = stc$cv), group = cv_groups(s$dt, attr(s$folds, "block_km")))
  print(cvp)
  decide_stage("fields", stage_candidates("fields", s, d), cvp, cvp$model[1], st$table,
               iid_year_only = s$set$iid_year_only)
})
print(res)
if (!ok || inherits(res, "try-error")) stop("Smoke test failed")
cat("SMOKE DONE\n")
