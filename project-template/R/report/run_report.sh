#!/bin/bash
# Run every report computation on the server, in dependency order, with one
# log per step in logs/report/<species>/. Steps whose cache exists are skipped, so a rerun
# resumes. Run in a screen session, passing LD_LIBRARY_PATH (screen drops it, and sf then
# cannot load GDAL):
#   screen -dmS report-<sp> bash -c "LD_LIBRARY_PATH='$LD_LIBRARY_PATH' R/report/run_report.sh <sp>"
# R_LIBS points to the library with sdmTMBexperiments >= 0.1.12 (density_share(), drop_isolated and the
# prediction-grid plot method); the selection caches stay on the version they were made with.
set -u
sp=${1:-report}   # a label for the logs; the species comes from config.yaml
cd "$(dirname "$0")/../.."
export R_LIBS=${R_LIBS:-$HOME/local/rlib-report}
L=logs/report/$sp; mkdir -p "$L"
C=${REPORT_CACHE:-data/output/report}   # <OUTPUT_DIR>/report; set REPORT_CACHE if OUTPUT_DIR differs
run() {  # run <log name> <cache file> <args...>
  local name=$1 cache=$2; shift 2
  if [ -n "$cache" ] && [ -f "$C/$cache" ]; then echo "$(date +%T) $name: cached"; return 0; fi
  echo "$(date +%T) $name: start"
  Rscript R/report/report_compute.R "$sp" "$@" > "$L/$name.log" 2>&1
  local rc=$?
  echo "$(date +%T) $name: exit $rc"
  return $rc
}
run grid prediction-grid.rds grid || exit 1
# The three products in parallel; each post step follows its own fit.
for p in total-iid fishable-iid total-ar1; do
  ( run fit-$p fit-$p.rds fit $p && run post-$p post-$p.rds post $p && run index-bc-$p index-bc-$p.rds index-bc $p ) &
done
# The sensitivity analyses need the total biomass (IID) fit and its index.
while [ ! -f "$C/post-total-iid.rds" ]; do
  sleep 60
  if [ -f "$L/fit-total-iid.log" ] && grep -q "Execution halted" "$L/fit-total-iid.log"; then echo "total-iid fit failed"; wait; exit 1; fi
  if [ -f "$L/post-total-iid.log" ] && grep -q "Execution halted" "$L/post-total-iid.log"; then echo "total-iid post failed"; wait; exit 1; fi
done
run retro-total-iid retro-total-iid.rds retro total-iid 6 &
run surveys surveys.rds surveys 3 &
run loso loso.rds loso 7 &
run influence influence.rds influence 10 &
while [ ! -f "$C/post-fishable-iid.rds" ]; do
  sleep 60
  if [ -f "$L/post-fishable-iid.log" ] && grep -q "Execution halted" "$L/post-fishable-iid.log"; then break; fi
  if [ -f "$L/fit-fishable-iid.log" ] && grep -q "Execution halted" "$L/fit-fishable-iid.log"; then break; fi
done
[ -f "$C/fit-fishable-iid.rds" ] && run retro-fishable-iid retro-fishable-iid.rds retro fishable-iid 6 &
wait
echo "$(date +%T) ALL DONE $sp"
