---
name: index-install
description: Install or set up index-wise for building sdmTMB survey indices. Use when the user says "install index-wise", "install https://github.com/DeepWaterIMR/index-wise", "set up index-wise", or first asks to build a survey index and index-wise is not yet installed. Runs onboarding: ensure BAIT, clone index-wise, install skills globally, verify R packages.
---

# Install index-wise

Goal: get index-wise working **once per machine** so it's available in **every** project
— not copied into each repo. index-wise builds on BAIT, so BAIT must be present first.

> Trigger: the user prompts *"install https://github.com/DeepWaterIMR/index-wise"* (or
> similar), or asks to build a survey index with no install yet.

## Step 1 — BAIT + privacy (defer to BAIT)

index-wise does **not** define its own privacy gate — it reuses BAIT's.

1. Check `~/.bait/config.json`. If BAIT is **not** installed, run BAIT's
   `bait-install` skill first (`install https://github.com/DeepWaterIMR/BAIT`). That handles
   the one-time model-training/data-retention onboarding and records `privacy_onboarded_at`.
2. If BAIT is installed and onboarding is recorded, **do not re-gate** — a short reminder that
   raw Biotic data stays local is enough. See BAIT's `biotic-privacy` skill.

Before generating scientific reports, also ensure wise-writing is installed and its
`academic-style`, `academic-conventions`, and `academic-data-report` skills are available.
Use `academic-writing-install` when needed. See `knowledge/wise-writing.md`.

## Step 2 — Clone index-wise to a sensible place

Clone next to BAIT (read `bait_path` from `~/.bait/config.json` and use its parent), or another
user-space location the user prefers. **Never** clone at a filesystem root or system directory.

```bash
git clone https://github.com/DeepWaterIMR/index-wise "<path>/index-wise"
```

If the user started by cloning the URL into the current workspace, reuse that clone instead of
duplicating it.

## Step 3 — Install skills globally

Sync each `index-*` skill directory separately so any `rsync --delete` is scoped to one
pack-owned folder. On first migration, compare and back up same-named legacy Codex skills,
then move those old folders aside so they do not remain active:

- Claude Code → `~/.claude/skills/`
- Codex → `~/.agents/skills/`
- Other agents → point their project/agent instructions at `<index-wise>/skills/`.

On macOS/Linux, sync the managed skills with:

```bash
backup=""
for destination in ~/.claude/skills ~/.agents/skills; do
  for source in "<index-wise>/skills"/index-*; do
    [ -d "$source" ] || continue
    name=${source##*/}
    if [ -d "$HOME/.codex/skills/$name" ]; then
      [ -n "$backup" ] || backup=$(mktemp -d "$HOME/.codex/skills-backup.XXXXXX")
      diff -qr "$HOME/.codex/skills/$name" "$source" || \
        echo "Legacy $name differed; its full copy will be preserved in $backup."
    fi
    mkdir -p "$destination/$name"
    rsync -a --delete "$source/" "$destination/$name/"
    if [ "$destination" = "$HOME/.agents/skills" ] && [ -d "$HOME/.codex/skills/$name" ]; then
      mv "$HOME/.codex/skills/$name" "$backup/"
    fi
  done
done
```

On Windows, use the same sequence: compare each `skills/index-*` folder with any matching
`$HOME/.codex/skills/index-*`, move that exact old folder to a dated backup, then use
`robocopy /E /PURGE` with the destination set to the matching `~/.agents/skills/index-*`
directory (and separately to Claude's directory). Never target the whole skills directory.
Unrelated legacy folders remain in place. Reconcile any differences from the saved copies
into the index-wise source before a later sync.

Record the install in `~/.index-wise/config.json`:

```json
{ "index_template_path": "<path>/index-wise", "installed_at": "<date>" }
```

Keep the `index_template_path` key for compatibility. The scaffold checks this canonical
file first, then falls back to the legacy `~/.index-template/config.json`.

## Step 4 — Verify the R toolchain

Confirm the modelling packages are installed (see `knowledge/packages.md`):

```r
for (p in c("sdmTMB", "ggOceanMaps", "sf", "quarto"))
  if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
if (!requireNamespace("sdmTMBexperiments", quietly = TRUE))
  remotes::install_github("DeepWaterIMR/sdmTMBexperiments")
library(sdmTMBexperiments)  # attaches ggOceanMaps
```

Confirm BAIT can reach the Biotic database (BAIT `biotic-connect`). If the database is missing,
point the user to BAIT `biotic-server-setup`.

## Done

Tell the user index-wise is installed and how to start:

> *"Let's make a biomass index for `<species>` using all bottom trawl data collected during
> surveys, using index-wise."*

That triggers `index-new-project`.
