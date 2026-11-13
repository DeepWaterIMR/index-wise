#!/usr/bin/env bash
# Render one Quarto document with a timestamped log in logs/. Made to run detached:
#   RENDER_LD_LIBRARY_PATH="$LD_LIBRARY_PATH" screen -dmS <species>-validate ./render.sh docs/sdmtmb/validation/validate.qmd -P key:value
# (with DOCS_DIR "docs/benchmark" the path is docs/benchmark/sdmtmb/validation/validate.qmd)
# Usage: ./render.sh <document.qmd> [extra quarto args]
set -u
cd "$(dirname "$0")"
qmd="$1"; shift
log="logs/$(basename "$qmd" .qmd)-$(date +%Y%m%d-%H%M%S).log"
mkdir -p logs

# A UTF-8 locale is required: without it Norwegian letters, Greek table headers and em dashes
# in captions are written as <U+00E5>-style escapes.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
# Servers that keep Quarto in a user-local folder or R in an environment module: adjust here.
export PATH="$HOME/local/bin:$PATH"

# screen is setgid on many servers, so the dynamic loader drops LD_LIBRARY_PATH inside it and
# sf cannot load libgdal ("Required R package(s) are missing: sf, ..."). Carry the value in
# RENDER_LD_LIBRARY_PATH, which screen keeps:
#   RENDER_LD_LIBRARY_PATH="$LD_LIBRARY_PATH" screen -dmS <name> ./render.sh <document.qmd>
# Without it, the value seen by the last render.sh run outside screen (logs/.ld_library_path)
# is used.
if [ -n "${RENDER_LD_LIBRARY_PATH:-}" ]; then
  export LD_LIBRARY_PATH="$RENDER_LD_LIBRARY_PATH"
elif [ -z "${LD_LIBRARY_PATH:-}" ] && [ -s logs/.ld_library_path ]; then
  export LD_LIBRARY_PATH="$(cat logs/.ld_library_path)"
fi
[ -n "${LD_LIBRARY_PATH:-}" ] && printf '%s' "$LD_LIBRARY_PATH" > logs/.ld_library_path

echo "Rendering $qmd -> $log"
{
  echo "host: $(hostname)  start: $(date)  commit: $(git rev-parse --short HEAD 2>/dev/null)"
  echo "R: $(command -v R)  quarto: $(command -v quarto)"
  quarto render "$qmd" "$@"
  status=$?
  echo "end: $(date)  exit: $status"
} > "$log" 2>&1
