# Command-line entry to the report computations (see R/report/report_lib.R).
#   Rscript R/report/report_compute.R <stock> <step> [product|name] [n_workers]
a <- commandArgs(trailingOnly = TRUE)
index_species <- a[1]
step <- a[2]
source(here::here("R", "0_setup.R"))
suppressPackageStartupMessages(library(sdmTMBexperiments))
source(here::here("R", "report_helpers.R"))
source(here::here("R", "plot_helpers.R"))
source(here::here("R", "compile_functions.R"))   # add_fishable_biomass() for a sensitivity
source(here::here("R", "report", "report_lib.R"))
# Light listings for R/report/run_report.sh; no model data needed.
if (step == "sens-names") {
  cat(names(report_sensitivities(cfg)), sep = "\n")
  quit(save = "no")
}
message("sdmTMBexperiments ", packageVersion("sdmTMBexperiments"), "; step ", step, "; ", Sys.time())
ctx <- report_context(cfg, out_dir, dt_crs)
if (step == "products") {
  cat(vapply(ctx$products, `[[`, "", "file"), sep = "\n")
  quit(save = "no")
}
report_check_stamp(ctx, cfg)
grid <- report_grid(ctx, cfg, dt_crs)
label_of <- function(file) names(ctx$products)[vapply(ctx$products, `[[`, "", "file") == file]
num <- function(x, default) if (is.na(x)) default else as.integer(x)
switch(step,
  grid = message("Grid: ", nrow(grid) / length(unique(grid$year)), " cells per year"),
  fit = run_report_fit(ctx, label_of(a[3])),
  post = run_report_post(ctx, label_of(a[3]), grid),
  "index-bc" = run_report_index_bc(ctx, label_of(a[3]), grid),
  retro = run_report_retro(ctx, label_of(a[3]), grid, n_workers = num(a[4], 6)),
  surveys = run_report_surveys(ctx, grid, n_workers = num(a[3], 3)),
  loso = run_report_loso(ctx, grid, n_workers = num(a[3], 7)),
  sens = run_report_sensitivity(ctx, grid, a[3]),
  influence = run_report_influence(ctx, grid, n_workers = num(a[3], 10)),
  stop("Unknown step ", step)
)
message("STEP DONE ", step, " ", paste(a[-(1:2)], collapse = " "), " ", Sys.time())
