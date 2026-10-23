---
name: index-update
description: Update index-wise to the latest version — git pull the index-wise repo and re-sync the index-* skills into the global skills folder. Use when the user says "update index-wise", "pull the latest index-wise", or asks for newer index-building recipes/skills.
---

# Update index-wise

Goal: pull the latest index-wise and re-sync its skills, mirroring BAIT's `bait-update`.

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
backup=""
for source in "<index-wise>/skills"/index-*; do
  [ -d "$source" ] || continue
  name=${source##*/}
  if [ -d "$legacy/$name" ]; then
    [ -n "$backup" ] || backup=$(mktemp -d "$HOME/.codex/skills-backup.XXXXXX")
    diff -qr "$legacy/$name" "$source" || \
      echo "Legacy $name differed; its full copy will be preserved in $backup."
  fi
  for destination in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    mkdir -p "$destination/$name"
    rsync -a --delete "$source/" "$destination/$name/"
  done
  if [ -d "$legacy/$name" ]; then mv "$legacy/$name" "$backup/"; fi
done
```

On Windows, use `robocopy /E /PURGE` in the same per-skill loop, targeting only the matching
`index-*` destination folder. Move matching legacy copies to a dated backup after comparing
them. Unrelated skills and BAIT's `biotic-*` folders remain untouched. Reconcile any wanted
legacy edits into the index-wise source before a later sync.

## Step 4 — Report

Summarise what changed (new/updated skills or knowledge files) from the git log since the last
pull, and remind the user that existing generated projects are unaffected — they can adopt new
guidance on their next task.
