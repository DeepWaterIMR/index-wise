source("project-template/R/assessment_index_handoff.R")
index <- data.frame(year = 2020:2021, est = c(10, 12), lwr = c(8, 9), upr = c(12, 15), se = c(.1, .2))
metadata <- list(units = "relative", uncertainty = list(column = "se", scale = "log", measure = "standard_error"), index_type = "survey biomass",
                 timing = .5, spatial_scope = "synthetic", provenance = list(project = "test"))
handoff <- build_assessment_index_handoff(list(total = index), "total", metadata)
stopifnot(identical(handoff$schema_version, 1L), identical(handoff$selected_name, "total"),
          identical(handoff$observations, index), identical(handoff$metadata, metadata))
stopifnot(inherits(try(build_assessment_index_handoff(list(total = index), "missing", metadata),
                       silent = TRUE), "try-error"))
message("Synthetic assessment-index producer contract passed.")
