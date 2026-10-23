# wise-writing compatibility

index-wise owns the survey-index method. **wise-writing owns the writing and
artifact conventions for every file produced in a generated project**, including prose,
R scripts, figures, tables, bibliographies, and agent instructions.

Before creating or revising project artifacts, read the installed `academic-style`,
`academic-conventions`, and `academic-data-report` skills and their applicable references.
If they are unavailable, use `academic-writing-install` or install
https://github.com/DeepWaterIMR/wise-writing before generating a scientific report.
Do not vendor copies of the skills: read the installed versions so improvements propagate.

## Layout and document type

Use `knowledge/project-structure.md`. All five workflow documents are **HTML data reports**
under `docs/data-report/`, with one directory per report; species-specific final reports
keep their optional section includes alongside them. Includes inherit their parent report's
metadata, format, and style and are not rendered independently. Add a website only when
requested, under `website/`. Other requested document types use the appropriate
wise-writing skill and a sibling folder under `docs/`.

`R/0_setup.R` declares packages, configuration, and the default ggplot theme. Number additional
pipeline scripts by run order (`1_data.R`, `2_analysis.R`); function libraries remain
un-numbered and use Roxygen2 documentation. `docs/render.R` is the render entry point.
Project-root `.here` and `_quarto.yml` support editor Preview before Git initialization.

## Report contract

- Preserve accountable human authors and affiliations. The scaffold accepts wise-writing's
  `AUTHORS`/`AFFILIATIONS` configuration, validates affiliation IDs, and serializes it as YAML.
  Confirm human metadata during the new-project questionnaire; never invent it.
- Keep `published-title: "Version"`, an ISO date, American English (`en-US`), HTML output,
  a title-matched `toc-title`, `code-fold: true`, and `code-summary: "Show code"`.
  Do not globally disable `echo`; all analytical steps must remain inspectable.
- Default figure widths are 6.69 or 3.35 inches (170 or 85 mm), with `theme_bw(base_size = 12)`.
  Keep JPEG figures and compact HTML. Use ggOceanMaps for static maps and preserve supplied
  geometries. Respect explicit author overrides.
- Use Purpose, Data, analysis sections appropriate to the workflow step, Results and
  recommendations, Software and reproducibility, unnumbered References, and a folded script
  appendix. Preserve methodological detail and uncertainties while adapting the skeleton.
- Write Methods and Results in past tense; use inline R for every data-derived value.
  Give each figure/table a caption and an interpretive sentence with a cross-reference.
  Split multi-plot chunks when separate captions or cross-references are needed.
- Keep verified literature in `docs/assets/references.bib` and use the shared ICES JMS CSL.
  `report_software()` generates report-specific software BibTeX using installed `citation()`
  metadata and emits narrative citations and versions. Customize its package list to include
  every package that influenced that document, including data acquisition and optional analyses.
  Cite Quarto too when used, using verified official citation metadata.
- Replace draft AI-disclosure instructions with the exact researcher-confirmed model list
  and roles; append to existing lists. Never imply that an author has approved an unreviewed
  draft. Researcher accountability remains explicit.
- Disclose every script used by a report in the appendix, in run order, using actual paths.
  Keep references before all appendices. Do not hide missing scripts with fallback text.
- Initialize a local Git repository when creating a project; do not add remotes, commit, or
  push without the user's authorization. VERSION starts at 0.1.0 with the scaffold date;
  update it deliberately with subsequent project revisions.

## Validation

Before expensive execution, check R syntax, YAML, paths, metadata, citations, cross-references,
figure captions, code visibility, and preservation of sampling/model-selection contracts.
Use synthetic fixtures for scaffold checks. Never run the confidential analysis merely to
check layout. Review first, then use `index-render` for real data/model renders and inspect
HTML navigation, title block, references, and folded code. Skeletons still require species-
specific implementation and researcher review; scaffolding is not a completed analysis.

This layout applies to **new projects**. Do not silently migrate existing species projects.
