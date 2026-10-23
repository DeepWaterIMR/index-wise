# data/output/

Cached **model outputs** — **git-ignored**. The documents write here so re-renders can load
instead of recomputing (toggle-controlled; see the index-wise `rendering.md`).

Typical contents (created by the workflow):
- `compiled-data.rds` — the filtered, de-duplicated dataset with true zeros.
- `model-fit-*.rds` — fitted sdmTMB models.
- `prediction-grid.rds` — the prediction grid (X, Y in km, depth, years).
- `predictions-*.rds` — grid predictions.
- `index-*.rds` — computed indices (`year, est, lwr, upr, se`), including the exported
  assessment index.

Nothing here is committed. Regenerate from the qmds + `config.yaml`.
