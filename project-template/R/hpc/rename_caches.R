# Rename selection caches copied from a cluster (e.g. Olivia) to the names this R session expects. The cache file
# name ends in substr(rlang::hash(candidate name), 1, 6), and that hash differs between R/rlang
# versions (Olivia R 4.4.2 vs Eucleia R 4.6.1), so copied caches are otherwise not found and
# would be refitted.
#   Rscript R/hpc/rename_caches.R <species>
a <- commandArgs(trailingOnly = TRUE)
source(here::here("R", "validation", "stage_lib.R"))
s <- stage_setup(a[1])
stage_files <- list.files(s$sel_dir, "^stage-(fields|geometry|fixed|family|mesh)\\.rds$", full.names = TRUE)
nms <- unique(c(mesh_ladder(s$cfg),
                unlist(lapply(stage_files, function(f) { r <- readRDS(f); c(names(r$specs), r$table$model) })),
                unlist(lapply(c("fields", "geometry", "fixed", "family"), function(st)
                  names(stage_candidates(st, s, read_decisions(s)))))))
slug <- function(x) gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(x)))
want <- setNames(vapply(nms, sdmTMBexperiments:::.selection_slug, ""), slug(nms))
files <- list.files(s$sel_dir, "^(mesh-spacetime|v-[a-z]+)-.*\\.rds$")
n <- 0
for (f in files) {
  m <- regmatches(f, regexec("^(mesh-spacetime|v-[a-z]+)-(.+)-([0-9a-f]{6})(-cv|-index)?\\.rds$", f))[[1]]
  if (!length(m)) next
  target <- want[m[3]]
  if (is.na(target) || target == paste0(m[3], "-", m[4])) next
  new <- paste0(m[2], "-", target, m[5], ".rds")
  file.rename(file.path(s$sel_dir, f), file.path(s$sel_dir, new)); n <- n + 1
}
unmatched <- setdiff(unique(sub("-[0-9a-f]{6}(-cv|-index)?\\.rds$", "", files)),
                     paste0(rep(c("mesh-spacetime", paste0("v-", c("fields", "geometry", "fixed", "family"))), each = length(want)), "-", names(want)))
cat("renamed", n, "files;", if (length(unmatched)) paste("unmatched:", paste(unmatched, collapse = ", ")) else "all matched", "\nRENAME DONE\n")
