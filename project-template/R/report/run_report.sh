#!/bin/bash
# Run every report computation for one stock on the server, in dependency order, with one log
# per step in logs/report/<stock>/. Steps whose cache exists are skipped, so a rerun resumes;
# the first step stamps the specification and later steps stop if it changed
# (report_check_stamp()). Run in a screen session, passing LD_LIBRARY_PATH (screen drops it, and
# sf then cannot load GDAL):
#   screen -dmS report-<stock> bash -c "LD_LIBRARY_PATH='$LD_LIBRARY_PATH' R/report/run_report.sh <stock>"
# The selection, the report and the documents use the same R library (R/0_setup.R checks the
# sdmTMBexperiments version). Ends with "ALL DONE <stock>".
set -u
sp=${1:?usage: R/report/run_report.sh <stock>}
cd "$(dirname "$0")/../.."
L=logs/report/$sp; mkdir -p "$L"
C=${OUTPUT_DIR:-data/output}/$sp/report   # set OUTPUT_DIR when config.yaml changes it
run() {  # run <log name> <cache file> <args...>
  local name=$1 cache=$2; shift 2
  if [ -n "$cache" ] && [ -f "$C/$cache" ]; then echo "$(date +%T) $name: cached"; return 0; fi
  echo "$(date +%T) $name: start"
  Rscript R/report/report_compute.R "$sp" "$@" > "$L/$name.log" 2>&1
  local rc=$?
  echo "$(date +%T) $name: exit $rc"
  return $rc
}
failed() { [ -f "$L/$1.log" ] && grep -q "Execution halted" "$L/$1.log"; }
run grid prediction-grid.rds grid || exit 1
products=$(Rscript R/report/report_compute.R "$sp" products 2> "$L/products.err")
[ -n "$products" ] || { echo "could not list the products (see $L/products.err)"; exit 1; }
# The products in parallel; each post step follows its own fit.
for p in $products; do
  ( run fit-$p fit-$p.rds fit $p && run post-$p post-$p.rds post $p && run index-bc-$p index-bc-$p.rds index-bc $p ) &
done
# The sensitivity analyses need the total biomass (IID) fit and its index.
while [ ! -f "$C/post-total-iid.rds" ]; do
  sleep 60
  if failed fit-total-iid || failed post-total-iid; then echo "total-iid failed"; wait; exit 1; fi
done
run retro-total-iid retro-total-iid.rds retro total-iid 6 &
run surveys surveys.rds surveys 3 &
run loso loso.rds loso 7 &
run influence influence.rds influence 10 &
if echo "$products" | grep -qx fishable-iid; then
  while [ ! -f "$C/post-fishable-iid.rds" ]; do
    sleep 60
    if failed fit-fishable-iid || failed post-fishable-iid; then break; fi
  done
  [ -f "$C/fit-fishable-iid.rds" ] && run retro-fishable-iid retro-fishable-iid.rds retro fishable-iid 6 &
fi
for v in $(Rscript R/report/report_compute.R "$sp" sens-names 2> "$L/sens-names.err"); do
  run sens-$v sens-$v.rds sens $v &
done
wait
echo "$(date +%T) ALL DONE $sp"
