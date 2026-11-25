#!/bin/bash
# One candidate of one selection stage per array task (cluster; account and partition passed by driver.sh).
# Submitted by driver.sh: sbatch --array=1-N%K --export=ALL,SPECIES=..,STAGE=..,PHASE=..,NAMES=..,WORKERS=..
# The phase "cv" task fits the candidate and its 10 folds in parallel over --cpus-per-task workers.
source R/hpc/slurm/env.sh   # jobs start in the submit directory, the project root
name=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$NAMES")
slug=$(echo "$name" | tr -c 'A-Za-z0-9' '_')
log="logs/validate/$SPECIES/$STAGE-$PHASE-$slug.log"
mkdir -p "logs/validate/$SPECIES"
echo "$(date '+%F %T') task $SLURM_ARRAY_JOB_ID.$SLURM_ARRAY_TASK_ID on $(hostname): $name" >> "$log"
srun Rscript R/validation/run_candidate.R "$SPECIES" "$STAGE" "$name" "$PHASE" "$WORKERS" >> "$log" 2>&1
