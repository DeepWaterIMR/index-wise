#!/bin/bash
# Drive the model selection for one species on the cluster: each stage submits its candidates as a
# job array and waits for it (sbatch --wait), then assembles. Every candidate is cached, so a
# resubmitted driver resumes where it stopped. The driver itself only submits and waits.
#   source R/hpc/slurm/site.sh
#   sbatch --account=$ACCOUNT --partition=$PARTITION --export=ALL,SPECIES=<stock> R/hpc/slurm/driver.sh
# Optional: MESH_ASSUMED_KM=<km> runs stages 2-5 with that mesh alongside the mesh stage;
# SKIP_MESH=1 when the mesh arrays of an earlier driver are still running.
# After the run: copy data/output/<stock>/selection and logs/validate/<stock> back to the server
# (rsync -r), run R/hpc/rename_caches.R <stock>, then the grid stage and the validate document
# there (compute nodes cannot download bathymetry). Copy the logs of failed tasks back before
# deleting the staging folder.
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=1-12:00:00
#SBATCH --job-name=sel-driver
source R/hpc/slurm/env.sh   # jobs start in the submit directory, the project root
source R/hpc/slurm/resources.sh            # FIT_*, CV_*, ASM_* per species, from the pilot
# The driver's own memory request would be inherited by the jobs it submits (--export=ALL) and
# clash with their --mem-per-cpu ("SLURM_MEM_PER_CPU, ... are mutually exclusive").
unset SLURM_MEM_PER_NODE SLURM_MEM_PER_CPU SLURM_MEM_PER_GPU
sp="$SPECIES"; L="logs/validate/$sp"; mkdir -p "$L"
status() { echo "$(date '+%F %T') $*" | tee -a "$L/status.log"; }
slug() { echo "$1" | tr -c 'A-Za-z0-9' '_'; }
S=R/hpc/slurm

# Billing hours used so far by this run (all stocks), from the job IDs the drivers recorded.
used_bh() {
  local ids; ids=$(cat logs/validate/*/jobids.txt 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  [ -z "$ids" ] && { echo 0; return; }
  sacct -X -n -P -j "$ids" -o AllocTRES,ElapsedRaw 2>/dev/null |
    awk -F'|' '{ if (match($1, /billing=[0-9.]+/)) { b = substr($1, RSTART + 8, RLENGTH - 8); s += b * $2 / 3600 } } END { printf "%.0f", s }'
}
budget_check() {
  local u; u=$(used_bh)
  if [ "$u" -ge "$BUDGET_STOP_BH" ]; then status "BUDGET STOP: $u billing hours used (limit $BUDGET_STOP_BH)"; exit 2; fi
  status "budget: $u billing hours used so far"
}

# run_array <stage> <phase> <names-file> <cpus> <mem-per-cpu> <time>: up to 3 tries per candidate
run_array() {
  local stage=$1 phase=$2 file=$3 cpus=$4 mem=$5 time=$6 try todo n
  for try in 1 2 3; do
    todo="$L/$stage-$phase-$(basename "$file" .txt)-todo.txt"; : > "$todo"
    while IFS= read -r nm; do
      [ -z "$nm" ] && continue
      grep -q "CANDIDATE DONE" "$L/$stage-$phase-$(slug "$nm").log" 2>/dev/null || echo "$nm" >> "$todo"
    done < "$file"
    n=$(wc -l < "$todo"); [ "$n" -eq 0 ] && return 0
    budget_check
    # Re-read the resources, so that an edit (e.g. more memory after an out-of-memory failure)
    # applies to the next try of a running driver.
    source R/hpc/slurm/resources.sh
    case "$stage-$phase" in
      mesh-cv) ;;                                  # memory and time passed by run_mesh
      *-fit) mem=$FIT_MEM; time=$FIT_TIME ;;
      *-cv) mem=$CV_MEM; time=$CV_TIME ;;
    esac
    [ "$try" -gt 1 ] && [ -n "${RETRY_MEM_FACTOR:-}" ] && mem="$(( ${mem%M} * RETRY_MEM_FACTOR ))M"
    status "$stage $phase try $try: $n task(s), $cpus cpu x $mem, $time"
    sbatch --wait --parsable --account="$ACCOUNT" --partition="$PARTITION" --job-name="$sp-$stage-$phase" --array=1-"$n"%100 \
      --cpus-per-task="$cpus" --mem-per-cpu="$mem" --time="$time" \
      --output="$L/slurm-%x-%A_%a.out" \
      --export=ALL,SPECIES="$sp",STAGE="$stage",PHASE="$phase",NAMES="$todo",WORKERS="$cpus" \
      "$S/candidate.sh" >> "$L/jobids.txt" || true
  done
  status "$stage $phase: some candidates failed 3 times; continuing with what is cached"
}

assemble() {  # assemble <stage> <phase>
  sbatch --wait --parsable --account="$ACCOUNT" --partition="$PARTITION" --job-name="$sp-$1-asm" --mem="$ASM_MEM" --time="$ASM_TIME" \
    --output="$L/slurm-%x-%j.out" --export=ALL,SPECIES="$sp",STAGE="$1",PHASE="$2" \
    "$S/assemble.sh" >> "$L/jobids.txt" || true
  grep -q "ASSEMBLE DONE" "$L/$1-assemble-$2.log" 2>/dev/null || { status "$1 assemble $2 FAILED"; exit 1; }
}

names() {  # names <stage> -> $L/<stage>-names.txt (light: lists the candidates)
  Rscript R/validation/assemble_stage.R "$sp" "$1" names 2> "$L/$1-names.err" | sed '/ASSEMBLE DONE/d' > "$L/$1-names.txt"
  [ -s "$L/$1-names.txt" ] || { status "$1: could not list candidates"; exit 1; }
}

status "start $sp on the cluster (driver job $SLURM_JOB_ID)"
echo "$SLURM_JOB_ID" >> "$L/jobids.txt"
run_mesh() {
  names mesh
  # The finest cutoff, if it needs more memory and time, runs as its own array.
  if [ "$MESH_FINE_KM" != 0 ]; then
    grep -x "$MESH_FINE_KM km" "$L/mesh-names.txt" > "$L/mesh-fine.txt" || true
    grep -vx "$MESH_FINE_KM km" "$L/mesh-names.txt" > "$L/mesh-rest.txt"
    run_array mesh cv "$L/mesh-fine.txt" "$CV_CPUS" "$CV_MEM_FINE" "$CV_TIME_FINE" &
    run_array mesh cv "$L/mesh-rest.txt" "$CV_CPUS" "$CV_MEM_MESH" "$CV_TIME_MESH"
    wait
  else
    run_array mesh cv "$L/mesh-names.txt" "$CV_CPUS" "$CV_MEM_MESH" "$CV_TIME_MESH"
  fi
  assemble mesh final
  status "mesh done: $(grep 'Stage mesh' "$L/mesh-assemble-final.log" | tail -1)"
}
# MESH_ASSUMED_KM (sbatch --export): run stages 2-5 with that mesh while the mesh stage runs.
mesh_pid=""
# SKIP_MESH=1: the mesh arrays were submitted by an earlier driver and are still running.
if [ -z "${SKIP_MESH:-}" ] && [ ! -f "data/output/$sp/selection/stage-mesh.rds" ]; then
  if [ -n "${MESH_ASSUMED_KM:-}" ]; then
    status "mesh stage in parallel; stages 2-5 assume $MESH_ASSUMED_KM km"
    run_mesh & mesh_pid=$!
  else
    run_mesh
  fi
fi
for stage in fields geometry fixed family; do
  if [ -f "data/output/$sp/selection/stage-$stage.rds" ]; then status "$stage already done"; continue; fi
  names "$stage"
  status "$stage: fitting $(wc -l < "$L/$stage-names.txt") candidates"
  run_array "$stage" fit "$L/$stage-names.txt" 1 "$FIT_MEM" "$FIT_TIME"
  assemble "$stage" fit
  cp "data/output/$sp/selection/stage-$stage-shortlist.txt" "$L/$stage-shortlist.txt"
  status "$stage: cross-validating $(wc -l < "$L/$stage-shortlist.txt") candidates"
  run_array "$stage" cv "$L/$stage-shortlist.txt" "$CV_CPUS" "$CV_MEM" "$CV_TIME"
  assemble "$stage" final
  status "$stage done: $(grep 'Stage' "$L/$stage-assemble-final.log" | tail -1)"
done
[ -f "data/output/$sp/selection/stage-grid.rds" ] || assemble grid final
if [ -n "$mesh_pid" ]; then
  wait "$mesh_pid"
  picked=$(grep -o "carried '[0-9]* km'" "$L/mesh-assemble-final.log" | tail -1 | grep -o "[0-9]*")
  if [ "$picked" = "$MESH_ASSUMED_KM" ]; then status "mesh decision $picked km = assumed mesh: stages 2-5 stand"
  else status "MESH MISMATCH: mesh decision ${picked:-?} km, stages 2-5 ran with $MESH_ASSUMED_KM km; rerun needed"; fi
fi
status "all stages done for $sp"
