---
name: index-update
description: Update index-wise to the latest version — git pull the index-wise repo and re-sync the index-* skills into the global skills folder. Use when the user says "update index-wise", "pull the latest index-wise", or asks for newer index-building recipes/skills.
---

# Update index-wise

Goal: pull the latest index-wise and re-sync its skills, mirroring BAIT's `bait-update`.

For a direct machine-wide update, use `fiskwise-update` when the user chooses managed lifecycle.
If this skill was invoked by that workflow, handle only index-wise-specific work and leave
pulls, registry state, skill reconciliation, and dependency checks to the parent. The standalone
procedure remains available. Updating index-wise never refreshes the Biotic database; that is a
separate, explicit BAIT action.

## Step 1 — Locate the install

Read `index_template_path` from `~/.index-wise/config.json`. For existing installs, fall back
to `~/.index-template/config.json`. If neither config points to a git repo, tell the user to
run `index-install` first and stop.

## Step 2 — Pull

```bash
git -C "<index_template_path>" fetch --quiet
git -C "<index_template_path>" pull --ff-only
```

If the working tree has local changes, report them and let the user decide — don't discard
work.

## Step 3 — Re-sync skills globally

Sync each updated `skills/index-*` into its matching user-level folder, with deletion scoped
to that index-wise-owned folder. Back up and reconcile legacy Codex duplicates before moving
them out of the active legacy skills directory. This macOS/Linux example handles both:

```bash
legacy="$HOME/.codex/skills"
backup_root="$HOME/.agents/skill-backups/$(date +%Y%m%d-%H%M%S)"
resolve_path() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
for source in "<index-wise>/skills"/index-*; do
  [ -d "$source" ] || continue
  name=${source##*/}
  source_path=$(resolve_path "$source")
  legacy_backup=0
  if [ -L "$legacy/$name" ] && [ "$(resolve_path "$legacy/$name")" = "$source_path" ]; then
    legacy_backup=1 # Retire the duplicate link after the canonical link is verified.
  elif [ -e "$legacy/$name" ] || [ -L "$legacy/$name" ]; then
    diff -qr "$legacy/$name" "$source" || echo "Legacy $name differs; preserve it in $backup_root."
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
    mv "$legacy/$name" "$backup_root/codex-$name"
  fi
done
```

On Windows, resolve each source and destination link before acting. Leave a matching
canonical symbolic link in place. Move any differing destination folder or link to a dated
backup, then create a symbolic link to the source. After verifying the canonical Codex link,
archive a matching legacy `.codex` symlink itself. Unrelated skills and BAIT's `biotic-*`
folders remain untouched. Reconcile wanted edits from the backups into the index-wise source.

## Step 4 — Report

Summarise what changed (new/updated skills or knowledge files) from the git log since the last
pull, and remind the user that existing generated projects are unaffected — they can adopt new
guidance on their next task.

On Windows without symbolic-link privileges, copy each source skill into its own destination
folder instead. Verify its `SKILL.md` before retiring a legacy copy, and refresh copied skills
on updates. Do not require administrator privileges solely to install the knowledge pack.
