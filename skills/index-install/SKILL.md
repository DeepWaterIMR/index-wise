---
name: index-install
description: Install or set up index-wise for building sdmTMB survey indices. Use when the user says "install index-wise", "install https://github.com/DeepWaterIMR/index-wise", "set up index-wise", or first asks to build a survey index and index-wise is not yet installed. Runs onboarding: ensure BAIT, clone index-wise, install skills globally, verify R packages.
---

<!-- pack-resources:start -->
**Pack resources:** the `index-wise` root is `~/.index-wise/config.json` → `index_template_path`, else `~/.fiskwise/config.json` →
`components.index-wise.path`, else the checkout containing this skill. Paths such as `knowledge/`
and `project-template/` are relative to that root, never `../../` from a skills folder; resolve
links that leave this skill's folder against the source skill there. Use absolute paths.
<!-- pack-resources:end -->


# Install index-wise

Goal: get index-wise working **once per machine** so it's available in **every** project
— not copied into each repo. index-wise builds on BAIT, so BAIT must be present first.

> Trigger: the user prompts *"install https://github.com/DeepWaterIMR/index-wise"* (or
> similar), or asks to build a survey index with no install yet.

For a direct machine-wide install, use `fiskwise-install` when the user chooses managed
lifecycle. If this skill was invoked by that workflow, handle only index-wise-specific checks
and leave clone, registry, shared-skill registration, and dependency bookkeeping to the parent.
The standalone procedure below remains available.

## Step 1 — Check workflow dependencies when needed

index-wise does **not** define its own privacy gate. BAIT owns Biotic access and its privacy
onboarding; check or install BAIT when the user is ready to compile Biotic data, not merely to
install the index-wise knowledge pack.

1. Before data compilation, check `~/.bait/config.json`. If BAIT is not installed, run BAIT's
   `bait-install` skill; it handles one-time privacy onboarding and offers database setup
   separately. If onboarding is already recorded, do not re-gate routine work.
2. Before generating scientific reports, ensure wise-writing's `academic-style`,
   `academic-conventions`, and `academic-data-report` skills are available. Install/update
   wise-writing on demand when needed; its absence does not block standalone index-wise install
   or model work that does not produce those documents. See `knowledge/wise-writing.md`.

## Step 2 — Clone index-wise to a sensible place

Clone next to BAIT (read `bait_path` from `~/.bait/config.json` and use its parent), or another
user-space location the user prefers. **Never** clone at a filesystem root or system directory.

```bash
git clone https://github.com/DeepWaterIMR/index-wise "<path>/index-wise"
```

If the user started by cloning the URL into the current workspace, reuse that clone instead of
duplicating it.

## Step 3 — Install skills globally

Link each `index-*` skill directory directly to its source in this repository. On first
migration, compare and back up same-named legacy Codex skills, then move differing old
folders aside so duplicate copies do not remain active:

- Claude Code → `~/.claude/skills/`
- Codex → `~/.agents/skills/`
- Other agents → point their project/agent instructions at `<index-wise>/skills/`.

On macOS/Linux, sync the managed skills with:

```bash
backup_root="$HOME/.agents/skill-backups/$(date +%Y%m%d-%H%M%S)"
resolve_path() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
for source in "<index-wise>/skills"/index-*; do
  [ -d "$source" ] || continue
  name=${source##*/}
  source_path=$(resolve_path "$source")
  legacy="$HOME/.codex/skills/$name"
  legacy_backup=0
  if [ -L "$legacy" ] && [ "$(resolve_path "$legacy")" = "$source_path" ]; then
    legacy_backup=1 # Retire the duplicate link after the canonical link is verified.
  elif [ -e "$legacy" ] || [ -L "$legacy" ]; then
    diff -qr "$legacy" "$source" || echo "Legacy $name differs; preserve it in $backup_root."
    legacy_backup=1
  fi
  for destination in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    target="$destination/$name"
    if [ -L "$target" ] && [ "$(resolve_path "$target")" = "$source_path" ]; then
      continue
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
      mkdir -p "$backup_root"
      mv "$target" "$backup_root/$(basename "$(dirname "$destination")")-$name"
    fi
    mkdir -p "$destination"
    ln -s "$source_path" "$target"
  done
  if [ "$legacy_backup" = 1 ]; then
    mkdir -p "$backup_root"
    mv "$legacy" "$backup_root/codex-$name"
  fi
done
```

If a canonical destination is already a valid symlink to that exact source folder, leave it
in place; pulling the pack updates it automatically. Never copy or sync a source onto its own
symlink. Move differing destination folders or links to backup before replacing them. Once
the `~/.agents/skills/` link is confirmed, archive a matching legacy `.codex` symlink itself
with `mv`; this does not follow or remove its source.

On Windows, resolve each source and destination before acting. Leave an existing symbolic
link to the exact source in place. Back up any different folder or link before replacing it
with a symbolic link to the source. Move matching legacy Codex folders to a dated backup
after comparing them; leave unrelated legacy folders in place. Reconcile wanted differences
into the index-wise source before a later sync.

Record the install in `~/.index-wise/config.json`. In managed mode, leave registry and pack
config updates to `fiskwise-install`; it preserves the compatible `index_template_path` key.
For standalone installation:

```json
{ "index_template_path": "<path>/index-wise", "installed_at": "<date>" }
```

Keep the `index_template_path` key for compatibility. The scaffold checks this canonical
file first, then falls back to the legacy `~/.index-template/config.json`.

## Step 4 — Verify the R toolchain

Confirm the modelling packages are installed (see `knowledge/packages.md`). In
Fiskwise-managed mode, `fiskwise-install` uses the saved R-install consent and package helper;
do not run a second installer here. If installation is disabled, or the target project uses
`renv.lock`, only report what is missing and let the project/lifecycle owner decide. For a
standalone install, use this check only with the user's authorization to add missing packages:

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

On Windows without symbolic-link privileges, copy each source skill into its own destination
folder instead. Verify its `SKILL.md` before retiring a legacy copy, and refresh copied skills
on updates. Do not require administrator privileges solely to install the knowledge pack.
