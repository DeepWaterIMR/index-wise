#!/usr/bin/env bash
# Run every model step for one stock on the server, unattended, in the order of index-wise
# knowledge/pipeline.md (steps 6-10): first-model document, model selection (+ validate document), the
# selection's decisions into config.yaml, the report computations, the report and the summary.
#   RENDER_LD_LIBRARY_PATH="$LD_LIBRARY_PATH" screen -dmS models-<stock> R/run_models.sh <stock> [cv_workers] [cv_parallel]
# Progress: logs/models-<stock>.log (one line per step). Each step resumes from its caches, so a
# rerun continues where it stopped (delete logs/pipeline/<stock>-<step>.done to redo a step).
# The data (data/output, data/source) must be synced first, and old caches moved away for a
# full rerun (knowledge/pipeline.md, cache inventory).
set -u
cd "$(dirname "$0")/.."
sp="$1"; W="${2:-10}"; P="${3:-3}"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
[ -n "${RENDER_LD_LIBRARY_PATH:-}" ] && export LD_LIBRARY_PATH="$RENDER_LD_LIBRARY_PATH"
export RENDER_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
mkdir -p logs/pipeline
LOG="logs/pipeline/models-$sp.log"
say() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
# Document root (DOCS_DIR in config.yaml, default docs).
D=$(LC_ALL=en_US.UTF-8 Rscript -e 'x <- yaml::read_yaml("config.yaml")$DOCS_DIR; cat(if (is.null(x)) "docs" else x)')

# render_ok <qmd>: render with render.sh and check the exit status in its log.
render_ok() {
  local qmd=$1 name; name=$(basename "$qmd" .qmd)
  say "render $name: start"
  ./render.sh "$qmd"
  local log; log=$(ls -t logs/"$name"-*.log | head -1)
  if grep -q "exit: 0" "$log"; then say "render $name: done ($log)"; return 0; fi
  say "render $name: FAILED ($log)"; return 1
}
done_flag() { [ -f "logs/pipeline/$sp-$1.done" ]; }
mark() { touch "logs/pipeline/$sp-$1.done"; }

say "start $sp (commit $(git rev-parse --short HEAD))"
if ! done_flag fit; then render_ok "$D/sdmtmb/fit/$sp-4-fit.qmd" || exit 1; mark fit; fi

if ! done_flag selection; then
  R/validation/run_species.sh "$sp" "$W" "$P"
  if [ ! -f "data/output/$sp/selection/stage-grid.rds" ]; then say "selection: FAILED (see logs/validate/$sp/status.log)"; exit 1; fi
  vlog=$(ls -t logs/"$sp"-5-validate-*.log 2>/dev/null | head -1)
  grep -q "exit: 0" "$vlog" 2>/dev/null || { say "validate render FAILED ($vlog)"; exit 1; }
  say "selection and validate document done"; mark selection
fi

if ! done_flag sync; then
  Rscript R/validation/sync_final_model.R "$sp" > "logs/pipeline/$sp-sync.log" 2>&1
  grep -q "SYNC DONE" "logs/pipeline/$sp-sync.log" || { say "sync FAILED"; exit 1; }
  say "config.yaml: $(grep -E 'CHANGED|already matches|NOT APPLIED' "logs/pipeline/$sp-sync.log" | tr '\n' ';')"
  mark sync
fi

if ! done_flag report; then
  say "report computations: start"
  R/report/run_report.sh "$sp" >> "logs/pipeline/$sp-run_report.log" 2>&1
  grep -q "ALL DONE" "logs/pipeline/$sp-run_report.log" || { say "report computations FAILED"; exit 1; }
  say "report computations: done"; mark report
fi
if ! done_flag report-doc; then render_ok "$D/sdmtmb/$sp/$sp-6-report.qmd" || exit 1; mark report-doc; fi
if ! done_flag summary; then render_ok "$D/data/$sp-1-summary.qmd" || exit 1; mark summary; fi
say "ALL DONE $sp"
