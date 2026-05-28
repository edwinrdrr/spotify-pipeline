# Setup — reproduce this project end-to-end

`main` is currently at **Phase 11** (Level-3: 4 GCP projects + WIF). For the fastest
end-to-end reproduction, skip directly to:

1. [`01-prerequisites.md`](01-prerequisites.md) — install tools
2. [`02-spotify-app.md`](02-spotify-app.md) — register a Spotify app
3. [`12-level-3.md`](12-level-3.md) — bootstrap 4 projects + WIF + Environments + deploy

Docs 03–11 describe earlier phases' setups; they're still accurate **at their phase tag**
(`git checkout phase-N-...` and re-read that tag's `docs/setup/` for the Level-1 path).
On `main`, they're historical references — the Phase-11 reproducer is doc 12.

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
| 9 | [`09-slim-ci.md`](09-slim-ci.md) — Slim CI deferral + per-PR ephemeral schemas + auto-cleanup | 4 min |
| 10 | [`10-prod-gate.md`](10-prod-gate.md) — required-reviewer gate on prod via GitHub Environment | 2 min |
| 11 | [`11-terraform.md`](11-terraform.md) — Terraform-ize buckets/datasets/SAs/IAM/APIs/budget (Phase 10) | 5 min |
| 12 | [`12-level-3.md`](12-level-3.md) — Level-3 refactor: 4 GCP projects, WIF, multi-env Terraform (Phase 11) | 15 min |

Total: ~67 minutes through Phase 11. (Phase 11 dominates — 4 projects to provision + WIF + workflow migration.)

> **Reproducing an earlier phase**: this folder is always the setup for whatever is
> on `main`. To reproduce Phase N's state, `git checkout phase-N-tag` and read
> *that tag's* `docs/setup/` — it will only describe what Phase N needed.
> (E.g., Phase 1 had no GCP doc — `git checkout phase-1-mvp` to see that simpler layout.)
