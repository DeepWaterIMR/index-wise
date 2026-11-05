# Rendering, screen sessions, logs, and toggles

Fitting sdmTMB models and rendering the Quarto documents is **time-consuming** (minutes to
hours). Treat every render as expensive: review the code first, run it detached with a log,
and cache outputs so you only pay the cost once.

## 1. Review before you render

**Review the changed chunks/scripts before starting a render.** A bug found after a two-hour
render costs two hours. Use a careful self-review or an available code-review tool; the
`/code-review` command is optional and may not exist in every environment. Fix issues before
rendering.

## 2. Caching toggles

Each expensive document exposes toggles (in the YAML `params:` or a setup chunk) that switch
between *compute* and *load*:

```yaml
params:
  refit_model: true      # FALSE → load the saved fit from data/output instead of refitting
  recompute_grid: true   # FALSE → load the saved prediction grid
  bias_correct: false    # TRUE only for final index runs (slow)
```

Workflow: render once with the compute toggles `TRUE` (writes fits, grids, predictions,
indices to `data/output/`); then **flip them to `FALSE`** so subsequent renders load the saved
objects and finish in seconds. Never delete `.quarto/` to "force a clean build" — fix the load
paths instead.

### Per-candidate caches for the slow stages

A single toggle for a whole model-selection stage is the wrong granularity: a failure on the
last candidate discards every candidate before it, which is exactly what makes a long run
unrecoverable. `sdmTMBexperiments::sdmTMB_selection(cache_dir =)` writes **one `.rds` per
candidate**, so an interrupted stage resumes where it stopped. Give each stage its own
`cache_prefix`.

The same mechanism spreads a stage across R sessions. A large spatiotemporal fit can peak at
several GB, and a dozen accumulating in one process exhausts memory — at which point candidates
start failing for reasons that have nothing to do with the model. `only = "<candidate>"`
computes one candidate and reads the rest from cache, so a warming script can fan the work
across processes:

```bash
for c in "Full model" "No depth" "No month"; do
  Rscript -e "quarto::quarto_render('docs/data-report/validation/validate.qmd',
                                    execute_params = list(only = '$c'))"
done
```

Then render normally: every candidate is already cached, and the document assembles the tables
in seconds.

## 3. Run detached in a screen session

Run the render as a background process so it survives a closed terminal, and **write output to a
log in `logs/`**. `screen` or `tmux` can manage the process when installed:

```bash
screen -dmS <species>-fit bash -c '
  quarto render "docs/data-report/fit/fit.qmd" > "logs/fit-$(date +%Y%m%d-%H%M%S).log" 2>&1
'
```

On macOS/Linux without screen or tmux, use `nohup quarto render ... > logs/<doc>.log 2>&1 &`.
On Windows PowerShell, use `Start-Process quarto -ArgumentList @('render', '<document.qmd>')
-RedirectStandardOutput 'logs/<doc>.log' -RedirectStandardError 'logs/<doc>.log'`.

Then **tell the user the session name** and how to check it:

```
Rendering in screen session "<species>-fit". Attach with:  screen -r <species>-fit
Follow the log with:  tail -f logs/fit-*.log
```

- The template's `render.sh` wraps this: it writes a timestamped log with host, commit and
  exit status, and sets a UTF-8 locale. Without that locale, a detached render writes
  Norwegian letters, Greek table headers and em dashes in captions or `cat()` output as
  `<U+2014>`-style escapes. Use `screen -dmS <species>-fit ./render.sh <doc.qmd> -P key:value`.
- **A slow chunk on a laptop may be the machine, not the code.** Check `uptime` before
  concluding a fit is stuck: file-sync and antivirus daemons (OneDrive, Spotlight, Defender)
  have pushed the load average past 100 while a render looked hung. Run fits and long renders
  on the modelling server, including development checks.
- List sessions: `screen -ls`. Detach from inside: `Ctrl-a d`.
- **Suggest running on a server.** For big meshes / many length groups / bias correction,
  offer to run the render on a compute server to speed things up and free the laptop.
- Never block the chat waiting for a long render — start it, report the session, and move on.

### Unattended runs on a server: three silent killers

- **Parallel workers die on logout.** `future::multisession` workers are separate processes
  that systemd kills when the SSH session ends, even inside a detached `screen`. Use forked
  `future::multicore` workers (sdmTMBexperiments ≥ 0.1.9 does this for `n_workers > 1`; set it
  yourself in project chunks that call `future::plan()`).
- **Bias correction crashes without an error.** `get_index_split(bias_correct = TRUE)` on
  ~450 000-row chunks ended the R session silently; the render just stopped. Keep chunks at
  ~75 000 rows (`nsplit = NULL` in sdmTMBexperiments, or `ceiling(nrow(grid) / 75e3)`). To
  debug a silent crash, move the computation into a standalone `Rscript` with per-model
  `tryCatch()` and logging, run it in its own screen session, and fold it back afterwards.
- **Bias-corrected indices take hours.** `get_index_split(nsplit = 12, bias_correct = TRUE)`
  for nine models took 13.4 h single-threaded on one benchmark server. Plan it as an overnight
  run, and have the chain script restore the compute toggles after the HTML render (for
  example `git checkout -- <doc>.qmd` when the toggles were flipped by a `sed` in the script)
  so a following PDF or Word render loads instead of recomputing.
- **`LD_LIBRARY_PATH` is lost.** Non-interactive `ssh host cmd` and `screen` sessions can start
  without the login shell's `LD_LIBRARY_PATH`, so `sf` cannot find `libgdal`. Launch through a
  small wrapper script that exports the login shell's value before calling `Rscript`/`quarto`.

## 4. Figure and file-size hygiene

- **Per-chunk JPEG, not a global `fig-format: jpeg`.** Map chunks (`geom_raster()` over the
  grid, dense bubble maps) get `#| dev: jpeg` and `#| dev-args: !expr list(quality = 85)`;
  very tall multi-panel annual maps use `quality = 70` and `#| fig-dpi: 72`. Line plots, Q-Q
  plots and scatter plots stay png, which keeps text and points sharp. On one benchmark report
  this took a self-contained HTML from 70 MB to 32 MB.
- **Find the heavy figures before compressing.** In the self-contained HTML, measure each
  `data:image/(png|jpeg);base64,...` block (length × 3/4 ≈ bytes) and map it to the nearest
  preceding `id="fig-..."` anchor.
- Keep rendered **HTML as small as feasible**: sensible `fig-dpi` (~150–180 for screen), and
  avoid embedding huge point layers. Large length-group reports can reach tens of MB.
- **Brackets in captions break cross-references silently.** A `fig-cap` with length-interval
  notation such as `(0,10]` stops pandoc-crossref from registering the figure id; the figure
  renders, but `@fig-...` fails with only an "Unable to resolve crossref" log warning. Escape
  the brackets (a small `esc_cap()` helper) and grep the render log for that warning.
- **PDF output:** pdflatex has no Greek glyphs in text; write `$\rho$`, not ρ. Limit
  multi-model figures to the products that matter in the PDF (a `fig_models()` helper that
  returns all models for HTML and the first one or two for PDF).
- **Parameter tables: scientific notation for large values.** Near-zero variance terms (a
  smooth's SD, `sigma_O`) in `tidy(fit, "ran_pars", conf.int = TRUE)` give upper bounds of `Inf`
  or about 1e172. With `format.args = list(scientific = FALSE)` LaTeX prints a 173-digit number
  and the longtable runs off the page. Format values ≥ 1e4 in scientific notation
  (`format_par_value()` in `R/report_helpers.R`).
- **Word output.** Table helpers should write pandoc pipe tables
  (`knitr::kable(format = "pipe")`) for docx; flextable with a vector `digits` fails. Notes
  meant for every non-HTML format use `content-visible unless-format="html"`, not
  `when-format="pdf"`, and reduced-figure/table gates use `!knitr::is_html_output()`, not
  `knitr::is_latex_output()`, so Word gets them too.
- **Optional sections need a fallback chunk.** Each `*-section.qmd` starts with an
  unconditional chunk that defines the objects its inline R uses, so the document renders when
  the section is switched off.
- `docs/render.R` renders all documents and refreshes data; use it for a full rebuild, but
  the same review-then-screen-then-toggle discipline applies.
