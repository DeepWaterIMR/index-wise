#!/usr/bin/env bash
# Drive the model-selection stages for one stock on the server, with retries.
#   [MESH_PARALLEL=3] R/validation/run_species.sh <species> [cv_workers] [cv_parallel]
# Logs: logs/validate/<species>/. Progress: logs/validate/<species>/status.log.
# Every candidate is cached, so rerunning this script resumes where it stopped.
set -u
cd "$(dirname "$0")/../.."
sp="$1"; W="${2:-10}"; P="${3:-3}"
L="logs/validate/$sp"; mkdir -p "$L"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 OMP_NUM_THREADS=1
[ -n "${RENDER_LD_LIBRARY_PATH:-}" ] && export LD_LIBRARY_PATH="$RENDER_LD_LIBRARY_PATH"
status() { echo "$(date '+%F %T') $*" | tee -a "$L/status.log"; }
slug() { echo "$1" | tr -c 'A-Za-z0-9' '_'; }

# run_candidates <stage> <phase> <workers> <parallel> <names-file>
run_candidates() {
  local stage=$1 phase=$2 w=$3 p=$4 file=$5 try
  for try in 1 2 3; do
    local todo=()
    while IFS= read -r nm; do
      [ -z "$nm" ] && continue
      grep -q "CANDIDATE DONE" "$L/$stage-$phase-$(slug "$nm").log" 2>/dev/null || todo+=("$nm")
    done < "$file"
    [ ${#todo[@]} -eq 0 ] && return 0
    status "$stage $phase try $try: ${#todo[@]} candidate(s)"
    printf '%s\0' "${todo[@]}" | xargs -0 -P "$p" -I{} bash -c \
      'Rscript R/validation/run_candidate.R "$0" "$1" "$2" "$3" "$4" >> "$5/$1-$3-$(echo "$2" | tr -c "A-Za-z0-9" "_").log" 2>&1' \
      "$sp" "$stage" {} "$phase" "$w" "$L"
  done
  status "$stage $phase: some candidates failed 3 times; continuing with what is cached"
}

assemble() {  # assemble <stage> <phase>
  local try
  for try in 1 2; do
    Rscript R/validation/assemble_stage.R "$sp" "$1" "$2" >> "$L/$1-assemble-$2.log" 2>&1
    grep -q "ASSEMBLE DONE" "$L/$1-assemble-$2.log" && return 0
  done
  status "$1 assemble $2 FAILED"; return 1
}

status "start $sp (cv workers $W, parallel $P)"
# Stage 1 (mesh) first: every cutoff of MESH_LADDER_KM is cross-validated and the mesh decision
# (assemble_mesh()) is written to decisions.rds, which stages 2-5 read.
if [ ! -f "data/output/$sp/selection/stage-mesh.rds" ]; then
  Rscript R/validation/assemble_stage.R "$sp" mesh names 2> "$L/mesh-names.err" | sed '/ASSEMBLE DONE/d' > "$L/mesh-names.txt"
  [ -s "$L/mesh-names.txt" ] || { status "mesh: could not list the cutoffs"; exit 1; }
  status "mesh: cross-validating $(wc -l < "$L/mesh-names.txt") cutoffs"
  run_candidates mesh cv 5 "${MESH_PARALLEL:-3}" "$L/mesh-names.txt"
  assemble mesh final || exit 1
  status "mesh done: $(grep 'Stage mesh' "$L/mesh-assemble-final.log" | tail -1)"
fi
for stage in fields geometry fixed family; do
  if [ -f "data/output/$sp/selection/stage-$stage.rds" ]; then status "$stage already done"; continue; fi
  # (sed without -i: the in-place flag differs between GNU and BSD/macOS sed)
  Rscript R/validation/assemble_stage.R "$sp" "$stage" names 2> "$L/$stage-names.err" | sed '/ASSEMBLE DONE/d' > "$L/$stage-names.txt"
  [ -s "$L/$stage-names.txt" ] || { status "$stage: could not list candidates"; exit 1; }
  status "$stage: fitting $(wc -l < "$L/$stage-names.txt") candidates"
  run_candidates "$stage" fit 1 12 "$L/$stage-names.txt"
  assemble "$stage" fit || exit 1
  cp "data/output/$sp/selection/stage-$stage-shortlist.txt" "$L/$stage-shortlist.txt"
  status "$stage: cross-validating $(wc -l < "$L/$stage-shortlist.txt") candidates"
  run_candidates "$stage" cv "$W" "$P" "$L/$stage-shortlist.txt"
  assemble "$stage" final || exit 1
  status "$stage done: $(tail -n 3 "$L/$stage-assemble-final.log" | grep 'Stage' )"
done
[ -f "data/output/$sp/selection/stage-grid.rds" ] || assemble grid final
status "all stages done for $sp"
# The document only reads the caches.
status "rendering $sp-5-validate.qmd"
D=$(LC_ALL=en_US.UTF-8 Rscript -e 'x <- yaml::read_yaml("config.yaml")$DOCS_DIR; cat(if (is.null(x)) "docs" else x)')
./render.sh "$D/sdmtmb/validation/$sp-5-validate.qmd"
status "render finished: $(tail -n 1 "$(ls -t logs/$sp-5-validate-*.log | head -1)")"
