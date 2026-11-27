# Synthetic checks of project-template/R/validation/sync_lib.R (grid decision and the config
# edit of sync_final_model.R). Run from the index-wise repository root; needs no model packages.
source("project-template/R/validation/sync_lib.R")

# --- Grid decision ----------------------------------------------------------------------
gi <- rbind(
  data.frame(year = 2001:2010, est = 100, grid_km = 5),
  data.frame(year = 2001:2010, est = 100.5, grid_km = 10),   # 0.5 % off: within 1 %
  data.frame(year = 2001:2010, est = 100.8, grid_km = 20),   # 0.8 %: within 1 %
  data.frame(year = 2001:2010, est = 103, grid_km = 50))     # 3 %: outside
stopifnot(identical(grid_decision(gi), 20),
          identical(grid_decision(gi, current = 10), 10),
          identical(grid_decision(gi, current = 50), 20))

d <- list(mesh_km = 30, terms = c("s(depth)", "fmonth"), family = "delta_gamma_poisson",
          spatial = "on", spatiotemporal = list("iid", "off"), anisotropy = FALSE, year = TRUE,
          smoothed = list(year = FALSE, spatial = "off", spatiotemporal = "ar1"))

# --- Multi-stock config: values go into the stock's block --------------------------------
multi <- c(
  "SPECIES_SETTINGS:",
  "  ling:",
  "    SPECIES_NAME: \"Ling\"",
  "    MESH_CUTOFF_KM: 20                # first fit",
  "    FINAL_MODEL:",
  "      MESH_CUTOFF_KM: 20",
  "      TERMS: [\"s(depth)\"]",
  "      FAMILY: \"delta_lognormal\"   # stage 5",
  "      SPATIAL: \"on\"",
  "      SPATIOTEMPORAL: \"iid\"",
  "      ANISOTROPY: false",
  "  tusk:",
  "    SPECIES_NAME: \"Tusk\"",
  "",
  "GRID_KM: 10",
  "SMOOTHED_SPATIAL: \"off\"")
r <- sync_config_lines(multi, "ling", d, grid_km = 20)
y <- yaml::yaml.load(paste(r$lines, collapse = "\n"))
stopifnot(identical(y$SPECIES_SETTINGS$ling$FINAL_MODEL$MESH_CUTOFF_KM, 30L),
          identical(y$SPECIES_SETTINGS$ling$FINAL_MODEL$FAMILY, "delta_gamma_poisson_link"),
          identical(unlist(y$SPECIES_SETTINGS$ling$FINAL_MODEL$SPATIOTEMPORAL), c("iid", "off")),
          identical(y$SPECIES_SETTINGS$ling$MESH_CUTOFF_KM, 30L),
          identical(y$SPECIES_SETTINGS$ling$GRID_KM, 20L),
          identical(y$SPECIES_SETTINGS$ling$SMOOTHED_SPATIOTEMPORAL, "ar1"),
          identical(y$SPECIES_SETTINGS$tusk$SPECIES_NAME, "Tusk"),
          is.null(y$SPECIES_SETTINGS$tusk$FINAL_MODEL),
          identical(y$GRID_KM, 10L),
          any(grepl("# stage 5", r$lines, fixed = TRUE)))
# A second run changes nothing.
stopifnot(!length(sync_config_lines(r$lines, "ling", d, grid_km = 20)$changes))
# A stock without FINAL_MODEL gets a whole block.
r2 <- sync_config_lines(r$lines, "tusk", d)
y2 <- yaml::yaml.load(paste(r2$lines, collapse = "\n"))
stopifnot(identical(y2$SPECIES_SETTINGS$tusk$FINAL_MODEL$TERMS, c("s(depth)", "fmonth")),
          identical(y2$SPECIES_SETTINGS$ling$FINAL_MODEL$MESH_CUTOFF_KM, 30L))

# --- Flat single-stock config: top-level values, FINAL_MODEL: null replaced -------------
flat <- c("SPECIES_NAME: \"Cod\"", "GRID_KM: 10                # cells", "MESH_CUTOFF_KM: 60",
          "FINAL_MODEL: null", "SMOOTHED_SPATIAL: \"off\"", "SMOOTHED_SPATIOTEMPORAL: \"ar1\"",
          "OUTPUT_DIR: \"data/output\"")
r3 <- sync_config_lines(flat, "cod", d, grid_km = 20)
y3 <- yaml::yaml.load(paste(r3$lines, collapse = "\n"))
stopifnot(identical(y3$FINAL_MODEL$MESH_CUTOFF_KM, 30L), identical(y3$MESH_CUTOFF_KM, 30L),
          identical(y3$GRID_KM, 20L), identical(y3$OUTPUT_DIR, "data/output"),
          any(grepl("# cells", r3$lines, fixed = TRUE)),
          !length(sync_config_lines(r3$lines, "cod", d, grid_km = 20)$changes))
# Decisions the report cannot apply are reported.
stopifnot(length(sync_config_lines(flat, "cod", modifyList(d, list(barrier = TRUE)))$problems) == 1L)

# FINAL_MODEL$EFFORT only when the family stage compared density and catch + offset candidates.
stopifnot(is.null(y3$FINAL_MODEL$EFFORT))
y4 <- yaml::yaml.load(paste(sync_config_lines(flat, "cod", modifyList(d, list(offset = TRUE)))$lines, collapse = "\n"))
y5 <- yaml::yaml.load(paste(sync_config_lines(r3$lines, "cod", modifyList(d, list(offset = FALSE)))$lines, collapse = "\n"))
stopifnot(identical(y4$FINAL_MODEL$EFFORT, "offset"), identical(y5$FINAL_MODEL$EFFORT, "density"))

message("Synthetic validation-helper checks passed.")
