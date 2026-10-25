---
name: index-render
description: Render the (slow) Quarto index documents safely — code-review first, then run the render detached in a screen session with a log in logs/, tell the user the session name, suggest a server, and flip caching toggles to FALSE once outputs exist. Use whenever an index qmd needs compiling.
---

<!-- pack-resources:start -->
**Pack resources:** resolve `index-wise` from `~/.index-wise/config.json` → `index_template_path` (or
`~/.fiskwise/config.json` → `components.index-wise.path`). If neither exists, use the
checkout containing this skill, or locate/obtain the pack through its install instructions.
Paths such as `knowledge/`, `cookbook/`, `config/` and `project-template/` belong to that
repository, not the current research directory. For a copied skill, resolve a link that
leaves this skill's directory against the corresponding source skill under that root;
keep bundled `references/` links relative to the skill. Never assume `../../` from an
agent's global skills folder reaches the repository. Use absolute resolved script paths.
<!-- pack-resources:end -->


# Render index documents

Goal: run expensive Quarto renders without wasting compute or blocking the chat. Read
`knowledge/rendering.md`.

Before producing project files, read `knowledge/wise-writing.md` and the installed
`academic-style`, `academic-conventions`, and `academic-data-report` skills. Apply their
conventions to every generated artifact; retain index-wise's scientific workflow.

## Step 1 — Review before rendering (required)

**Do not render unreviewed code.** Review the changed qmd chunks and R scripts yourself or use
an available code-review tool, then fix issues first. A `/code-review` command is optional and
may not be installed in every agent environment.

## Step 2 — Check the toggles

- First run of a document: compute toggles (`refit_model`, `recompute_grid`, …) `TRUE`.
- Re-render after outputs exist in `data/output/`: flip them to `FALSE` so the render loads
  saved objects. `bias_correct` only `TRUE` for final index runs.

## Step 3 — Render detached with a log

Use a background process and save output to `logs/` so rendering can continue after the
conversation or terminal closes. `screen` is one option on systems where it is installed:

```bash
screen -dmS <slug>-<doc> bash -c '
  quarto render "docs/<path>/<doc>.qmd" > "logs/<doc>-$(date +%Y%m%d-%H%M%S).log" 2>&1
'
```

Portable fallback (macOS/Linux):

```bash
log="logs/<doc>-$(date +%Y%m%d-%H%M%S).log"
nohup quarto render "docs/<path>/<doc>.qmd" > "$log" 2>&1 < /dev/null &
echo "PID $!; log $log"
```

Windows PowerShell: `Start-Process quarto -ArgumentList @('render', 'docs/<path>/<doc>.qmd')
-RedirectStandardOutput 'logs/<doc>.log' -RedirectStandardError 'logs/<doc>.log'`.

Then tell the user:

> Rendering in screen session **`<slug>-<doc>`**. Attach: `screen -r <slug>-<doc>` · follow the
> log: `tail -f logs/<doc>-*.log` · list sessions: `screen -ls`.

## Step 4 — Suggest a server for heavy jobs

For big meshes, many length groups, CV, or bias correction, **offer to run the render on a
compute server** to speed it up and free the user's machine.

## Step 5 — After it finishes

- Confirm the expected `data/output/` files were written.
- Check the HTML size is reasonable (`fig-format: jpeg`, sensible dpi).
- Flip the compute toggles to `FALSE` for future re-renders.
- Do **not** delete `.quarto/` to "force a clean build" — fix load paths instead.

Never block the conversation waiting for a long render — start it, report the session, and
continue.
