# Shared environment for the cluster jobs of the model selection (Olivia, Sigma2). Sourced by every job script.
# RUN_DIR and R_LIBS_USER are set in R/hpc/slurm/site.sh, written when the Sigma2 folder is set up.
set -o errexit
source R/hpc/slurm/site.sh
module --quiet reset
module load NRIS/CPU 2>/dev/null
module load R/4.4.2-gfbf-2024a R-bundle-CRAN/2024.11-foss-2024a   # the R with the CRAN bundle (2026-11; hpc-wise knowledge/sigma2-olivia.md)
set -o nounset   # after the module calls, which use unset variables
export R_LIBS_USER LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 INDEX_HPC=1
cd "$RUN_DIR"
