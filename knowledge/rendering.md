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

- List sessions: `screen -ls`. Detach from inside: `Ctrl-a d`.
- **Suggest running on a server.** For big meshes / many length groups / bias correction,
  offer to run the render on a compute server to speed things up and free the laptop.
- Never block the chat waiting for a long render — start it, report the session, and move on.

## 4. Figure and file-size hygiene

- **Raster figures use `fig-format: jpeg`** (density maps, bathymetry). Vector for line plots.
- Keep rendered **HTML as small as feasible**: prefer jpeg rasters, sensible `fig-dpi`
  (~150–180 for screen), and avoid embedding huge point layers. Large length-group reports can
  reach tens of MB — watch the output size.
- `docs/render.R` renders all documents and refreshes data; use it for a full rebuild, but
  the same review-then-screen-then-toggle discipline applies.
