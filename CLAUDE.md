@AGENTS.md

# Claude Code notes

- **Skills** live in `~/.claude/skills/index-*`. When the user types `/index-...` or asks to
  build, validate or report an index, invoke the matching skill. Outside a scaffolded project,
  use `index-sdmtmb`. For Biotic data access, defer to BAIT's `biotic-*` skills.
- **Project memory, not local memory.** Inside a generated project, use its `ai/memory/`
  folder; do not put project facts in `~/.claude/projects/.../memory/`.
- **Plan mode** after the `index-new-project` questionnaire, before scaffolding and rendering.
- **Code review before render**; `/code-review` is optional. See `knowledge/rendering.md`.
