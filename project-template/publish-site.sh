#!/usr/bin/env bash
# Optional: copy the rendered HTML documents of DOCS_DIR into the public/<folder>/ folder of a
# website repository (e.g. GitLab Pages), keeping the folder structure so that links between
# the documents work. Only .html files are copied; commit and push in that repository. Never
# publish documents that show confidential data (see the project's data-confidentiality memory).
# Usage: ./publish-site.sh [path to the site clone]   (default SITE_DIR in config.yaml)
set -euo pipefail
cd "$(dirname "$0")"
cfg() { LC_ALL=en_US.UTF-8 Rscript -e "x <- yaml::read_yaml('config.yaml')\$$1; cat(if (is.null(x)) '$2' else x)"; }
docs=$(cfg DOCS_DIR docs)
site="${1:-$(cfg SITE_DIR '')}"
[ -n "$site" ] || { echo "Give the site clone as an argument or set SITE_DIR in config.yaml" >&2; exit 1; }
[ -d "$site/public" ] || { echo "No public/ folder in $site" >&2; exit 1; }
dest="$site/public/$(basename "$docs")"
rsync -a --prune-empty-dirs --include='*/' --include='*.html' --exclude='*' "$docs/" "$dest/"
echo "Copied to $dest:"
(cd "$site/public" && find "$(basename "$docs")" -name '*.html' | sort)
