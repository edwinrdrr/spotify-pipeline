# Setup — reproduce this project end-to-end

Follow these docs **in order** to reproduce what's currently on `main`.

| # | Doc | Time |
|---|-----|------|
| 1 | [`01-prerequisites.md`](01-prerequisites.md) — Spotify account, gcloud, Python, repo | 5 min |
| 2 | [`02-spotify-app.md`](02-spotify-app.md) — register a Spotify Developer app | 3 min |
| 3 | [`03-gcp-project.md`](03-gcp-project.md) — provision a GCP project + bucket + dataset + ADC | 8 min |
| 4 | [`04-run-end-to-end.md`](04-run-end-to-end.md) — `.env`, virtualenv, run the snapshot locally as a sanity check | 3 min |
| 5 | [`05-deploy-function.md`](05-deploy-function.md) — deploy as Cloud Function + daily Cloud Scheduler | 5 min |
| 6 | [`06-dbt-models.md`](06-dbt-models.md) — dbt staging + marts on top of the raw table | 5 min |
| 7 | [`07-ci-pipeline.md`](07-ci-pipeline.md) — GitHub Actions CI: `dbt build` on every PR | 5 min |
| 8 | [`08-multi-env.md`](08-multi-env.md) — dataset-suffix env split: `dev`/`ci`/`staging`/`prod` | 3 min |

Total: ~40 minutes through Phase 7.

> **Reproducing an earlier phase**: this folder is always the setup for whatever is
> on `main`. To reproduce Phase N's state, `git checkout phase-N-tag` and read
> *that tag's* `docs/setup/` — it will only describe what Phase N needed.
> (E.g., Phase 1 had no GCP doc — `git checkout phase-1-mvp` to see that simpler layout.)
