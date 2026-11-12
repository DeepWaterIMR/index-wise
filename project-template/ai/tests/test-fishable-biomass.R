# Independent checks of add_fishable_biomass() (R/compile_functions.R).
# Run from the project root: Rscript ai/tests/test-fishable-biomass.R
# 1. Synthetic hauls with hand-calculated answers.
# 2. Recomputation of the fishable share on the compiled data with separate base-R code.
suppressMessages({
  library(dplyr)
  `%||%` <- function(a, b) if (is.null(a)) b else a
  source("R/compile_functions.R")
})
ok <- function(cond, msg) { cat(if (all(cond)) "PASS" else "FAIL", "-", msg, "\n"); invisible(all(cond)) }

# --- 1. Synthetic --------------------------------------------------------------------------
lw <- list(a = 1e-5, b = 3)                 # W = 1e-5 L^3 kg
st <- tibble(
  haul_id = c("A", "B", "C", "D", "E"), missionid = c("m1", "m1", "m1", "m2", "m3"),
  cruiseseries = c("S", "S", "S", "S", "T"), year = 2000,
  biomass = c(10, 4, 6, 0, 3), swept_area = 0.02
)
len <- tibble(
  haul_id = c("A", "A", "B", "D"),
  length_cm = c(50, 100, 40, 80),           # haul A: one fish below, one above 73 cm
  raising = c(2, 1, 1, 1)                   # 50 cm fish represents two fish
)
res <- add_fishable_biomass(st, len, lw, 73)
wA <- c(2 * 1e-5 * 50^3, 1e-5 * 100^3)     # 2.5 kg, 10 kg
pA <- wA[2] / sum(wA)                       # 0.8
ok(abs(res$fishable_fraction[res$haul_id == "A"] - pA) < 1e-12, "haul A share = 10 / 12.5")
ok(abs(res$biomass_fishable[res$haul_id == "A"] - 10 * pA) < 1e-12, "haul A fishable = 8 kg")
ok(res$fishable_fraction[res$haul_id == "B"] == 0, "haul B (only small fish) share = 0")
# haul C: positive, no lengths -> biomass-weighted mean of survey m1 (A: 0.8 x 10, B: 0 x 4)
pC <- (0.8 * 10 + 0 * 4) / (10 + 4)
ok(abs(res$fishable_fraction[res$haul_id == "C"] - pC) < 1e-12 &&
     res$fishable_imputed[res$haul_id == "C"] == "survey mean", "haul C gets survey mean")
ok(res$biomass_fishable[res$haul_id == "D"] == 0, "zero haul D stays zero even with lengths")
ok(res$fishable_imputed[res$haul_id == "E"] == "none", "haul E with no lengths anywhere is flagged")
ok(all(abs(res$rho_biomass_fishable - res$biomass_fishable / res$swept_area) < 1e-12, na.rm = TRUE),
   "fishable density = fishable biomass / swept area")

# --- 2. Real data --------------------------------------------------------------------------
for (sp in "stock") {
  cfg <- yaml::read_yaml("config.yaml")
  out <- cfg$OUTPUT_DIR %||% "data/output"
  dt <- readRDS(file.path(out, "compiled-data.rds"))
  ln <- readRDS(file.path(out, "length-data.rds"))
  meta <- readRDS(file.path(out, "compile-metadata.rds"))
  w <- ln$raising * meta$lw$a * ln$length_cm^meta$lw$b
  num <- tapply(w * (ln$length_cm >= cfg$OVER_CM), ln$haul_id, sum)
  den <- tapply(w, ln$haul_id, sum)
  share <- num / den
  m <- dt[dt$fishable_imputed == "measured", ]
  diff <- abs(m$fishable_fraction - share[m$haul_id])
  ok(max(diff) < 1e-10, paste(sp, "- measured shares reproduced by independent code"))
  ok(all(dt$biomass_fishable <= dt$biomass + 1e-9), paste(sp, "- fishable <= total"))
  ok(all(dt$biomass_fishable[dt$biomass == 0] == 0), paste(sp, "- zero hauls zero"))
  ok(!any(is.na(dt$biomass_fishable)), paste(sp, "- no missing fishable biomass"))
  ok(all(dt$fishable_imputed[dt$biomass > 0] != "none"), paste(sp, "- every positive haul has a share"))
}
