#!/bin/bash
# Combine a stage's cached candidates (phase fit: shortlist; final: decision), decide the mesh
# (stage mesh) or compute the grid comparison (stage grid). Submitted by driver.sh with --wait (account and partition from site.sh).
#SBATCH --cpus-per-task=1
source R/hpc/slurm/env.sh   # jobs start in the submit directory, the project root
srun Rscript R/validation/assemble_stage.R "$SPECIES" "$STAGE" "$PHASE" >> "logs/validate/$SPECIES/$STAGE-assemble-$PHASE.log" 2>&1
