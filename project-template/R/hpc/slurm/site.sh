# Site settings for the cluster (written when the cluster folder is set up; hpc-wise sigma2-run).
# Sourced by env.sh and driver.sh. Fill in before the first submission.
ACCOUNT=nnXXXXk               # Sigma2 project account (sbatch --account)
PARTITION=small
RUN_DIR="/cluster/projects/nnXXXXk/USER/PROJECT"   # the staged project folder
R_LIBS_USER="/cluster/projects/nnXXXXk/USER/rlib/4.4.2"
BUDGET_STOP_BH=1000          # the driver stops submitting when the run has used this many billing hours
