---
name: index-review
description: Review an index-wise project (or the index-wise project template) for bugs, config–code drift, stale or inconsistent text, factual and methodological errors, broken Quarto mechanics, cache and pipeline faults, and privacy slips — a mechanical lint plus a checklist-driven reading review, ending in a ranked findings report. Use when the user asks to review, audit, check or proof-read an index project, before a benchmark or hand-off, after a large revision, or before an expensive full rerun.
---

<!-- pack-resources:start -->
**Pack resources:** the `index-wise` root is `~/.index-wise/config.json` → `index_template_path`, else `~/.fiskwise/config.json` →
`components.index-wise.path`, else the checkout containing this skill. Paths such as `knowledge/`
and `project-template/` are relative to that root, never `../../` from a skills folder; resolve
links that leave this skill's folder against the source skill there. Use absolute paths.
<!-- pack-resources:end -->


# Review an index project

Goal: find what is wrong before a reviewer, a working group or a rerun does. The review reads;
it does not fix. Findings go to the user ranked, with evidence, and are fixed only after they
agree. The checklist is `knowledge/review-checklist.md`; read it first.

## Step 0 — Scope and context

- **Target:** a generated project (default), or the pack template (`project-template/`,
  lint with `--template`). Ask only if unclear.
- **Extent:** the whole project, or what changed since a commit (`git diff <ref> --stat`).
  A diff review still checks the text and config that *depend on* the changed code.
- Read the project's `AGENTS.md`, `ai/memory/MEMORY.md` and the memory files it lists, and
  `config.yaml` with its comments. Recorded decisions are not defects; the documents must
  agree with them.

## Step 1 — Mechanical checks

From the project root:

```bash
Rscript "<index-wise>/skills/index-review/scripts/lint_project.R" .
```

It prints `SEVERITY  check  file:line  message` and exits 1 on any ERROR. ERROR is almost
certainly a bug; WARN needs a look; INFO (typed numbers in prose, optional keys read with `$`,
config keys with defaults in code, stale renders) is a reading list for Step 2. Then run the
project's own tests: every `ai/tests/test-*.R` (AI statement, stock parity, fishable biomass).
Report a failing test as a finding; do not edit the test to pass.

## Step 2 — Reading review

Walk the checklist sections A–H against the code, the documents and, where they exist, the
rendered HTML and `data/output/` files. Verify every claim against its source of truth:

- text ↔ `config.yaml` and the outputs it describes (numbers, model terms, family, mesh, grid,
  month, years, recommended index);
- documents ↔ each other (summary vs report vs validate; one stock vs another);
- code ↔ the rules in `knowledge/` (`data-filtering.md`, `model-selection.md`,
  `index-level-and-trend.md`, `influence-diagnostics.md`, `pipeline.md`);
- citations ↔ the claim they support.

For a large project, sweep the documents by checklist section in parallel subagents on a
cheaper model, each returning candidate findings with file:line and the evidence. Verify each
candidate here before reporting it; drop what you cannot reproduce.

## Step 3 — Report

Write `ai/reports/<YYYY-MM-DD>_project-review.md` (committed; no data values beyond what the
documents already publish) and summarise it to the user. One entry per finding, most severe
first:

| Field | Content |
|-------|---------|
| Severity | **bug** (wrong result) · **inconsistency** (text, config, code or documents disagree) · **text** (wording, overclaim, stale) · **hygiene** (dead code, privacy, mechanics) |
| Where | `file:line` (and the affected documents) |
| Evidence | what the code/output says vs what the text/config says |
| Fix | the smallest change, and which documents must be re-rendered |

End with what was not checked (e.g. renders not run, outputs absent). Ask which findings to
fix. After fixes, rerun the lint and tests, and re-render through `index-render`.

## Step 4 — Feed the checklist

A new kind of defect — one the checklist did not name — is a pack finding: record it and offer
a report through `fiskwise-feedback` (or a draft issue, see `AGENTS.md` "Reporting back"), so
the item and, where possible, a lint check are added. Add a mechanical check to
`scripts/lint_project.R` with a planted case in `scripts/test-lint.R`.
