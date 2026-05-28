# 08 — Multi-env via dataset suffix (Phase 7, Level 1)

You have a working CI pipeline (Phase 6). Now split the analytics layer into
**`dev` / `staging` / `prod`** — three BigQuery datasets inside the same one GCP
project, with separate deploy paths into each.

## What you'll have when done

| Dataset | Who writes to it | When |
|---|---|---|
| `spotify_raw` | Cloud Function | Daily cron (Phase 3) — **unchanged** |
| `spotify_analytics_dev` | Your laptop (ADC) | `dbt build` (default `target: dev`) |
| `spotify_analytics_ci` | dbt-ci SA | Per-PR validation (Phase 6 — **unchanged**) |
| `spotify_analytics_staging` | dbt-ci SA | **Auto** on merge to `main` |
| `spotify_analytics_prod` | dbt-ci SA | **Manual** via Actions UI `workflow_dispatch` |

The promote flow:
```
laptop dbt → dev          (write at will, dev is yours)
   ↓
open PR  → ci             (validates; PR doesn't touch dev/staging/prod)
   ↓ merge to main
   →     → staging        (auto)
   ↓ you click "Run workflow"
   →     → prod           (manual)
```

## Why dataset suffix (not per-env GCP projects)?

Phase 7 is **Level-1 isolation** — the cheapest pattern that gives real env separation:
- One GCP project, one billing target, one IAM scope
- Datasets are the boundary
- No new SAs, no per-env auth complexity

**Phase 11 (Level-3)** splits this into separate GCP projects per env (the
crypto-pipeline pattern). The dataset-suffix approach is genuinely fine until you need:
- Per-env IAM (different people own different envs)
- Per-env quotas
- Per-env cost attribution
- Audit clarity ("who wrote to prod?")

You won't need those for a learning project. You will need them at a real company.

## What's deliberately not in Phase 7 (deferred)

- **No required-reviewer on prod** — Phase 9 adds GitHub Environments with a manual
  approval gate. For now `workflow_dispatch` only requires repo-write.
- **No Slim CI / ephemeral PR schemas** — Phase 8 adds those (`state:modified.body+`,
  `dbt_ci_pr_<n>`).
- **No CI for ingestion** — only dbt has CI right now; Phase 12 (Terraform CI) covers
  infra; ingestion changes still rely on the Cloud Function deploy from Phase 3.
- **No per-env GCP projects** — Phase 11.

## Prerequisites

- Doc 07 ran (CI pipeline + `GCP_SA_KEY`/`GCP_PROJECT` repo secrets exist)
- The `dbt-ci` SA already has `bigquery.jobUser` + `bigquery.dataEditor` at project
  level (Phase 6 setup) — it can write to *any* dataset including the new
  `_staging` / `_prod` ones. No new IAM grants needed.

## Fast path

```bash
# 1. create the three env datasets (if you haven't already)
for env in dev staging prod; do
    bq --project_id="$GCP_PROJECT" mk --dataset --location=US "spotify_analytics_${env}"
done

# 2. (optional) delete the legacy spotify_analytics dataset from Phase 4-6
bq --project_id="$GCP_PROJECT" rm -r -d -f spotify_analytics

# 3. local dev — writes to spotify_analytics_dev by default
cd dbt
dbt build           # equivalent to `dbt build --target dev`

# 4. PR a change touching dbt/**  → CI builds against spotify_analytics_ci
# 5. Merge to main                → staging workflow auto-builds against spotify_analytics_staging
# 6. Promote to prod              → Actions → "dbt deploy → prod (manual)" → Run workflow
```

## The two new workflows

### `.github/workflows/dbt-deploy-staging.yml`

Triggers: `push` to `main` touching `dbt/**`, `requirements-dbt.txt`, or the workflow
itself. Same step shape as `dbt-ci.yml`; only the `--target` flag changes.

```yaml
- name: dbt build (--target staging)
  working-directory: dbt
  run: dbt build --target staging --no-partial-parse
```

### `.github/workflows/dbt-deploy-prod.yml`

Triggers: **`workflow_dispatch`** only. No automatic firing. Go to the repo →
Actions tab → "dbt deploy → prod (manual)" → "Run workflow" → Run on `main`.

```yaml
on:
  workflow_dispatch:
```

Phase 9 will add a GitHub Environment with required-reviewer protection so even the
dispatch needs approval; for now, anyone with repo-write can run it.

## Querying each env

```bash
# dev (what you last built locally)
bq query --use_legacy_sql=false --format=pretty --project_id="$GCP_PROJECT" \
  "SELECT artist_name, track_name, popularity, status
   FROM \`$GCP_PROJECT.spotify_analytics_dev.fct_track_popularity_daily\`
   ORDER BY popularity DESC LIMIT 5"

# staging (auto-built on last merge)
bq query --use_legacy_sql=false --format=pretty --project_id="$GCP_PROJECT" \
  "SELECT COUNT(*) FROM \`$GCP_PROJECT.spotify_analytics_staging.fct_track_popularity_daily\`"

# prod (only built when you click Run workflow)
bq query --use_legacy_sql=false --format=pretty --project_id="$GCP_PROJECT" \
  "SELECT COUNT(*) FROM \`$GCP_PROJECT.spotify_analytics_prod.fct_track_popularity_daily\`"
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Merge to main didn't trigger the staging workflow | Merge commit didn't touch `dbt/**` or the workflow file. | Trigger it manually: Actions → "dbt deploy → staging" → "Run workflow"; or wait for the next dbt-touching merge. |
| Local `dbt build` failed: `Not found: Dataset spotify_analytics_dev` | You skipped step 1 (create the env datasets). | Run the `bq mk` loop in "Fast path" step 1. |
| Staging workflow failed: `permission denied on spotify_analytics_staging` | The dbt-ci SA hasn't propagated `dataEditor`. | Re-run `setup-ci.sh` (doc 07) to refresh IAM, wait 30s. |
| Prod dataset has 0 rows | You haven't promoted yet — `workflow_dispatch` requires a click. | Actions → "dbt deploy → prod (manual)" → "Run workflow". |
| Mixed-up env: dev's tables show up in prod | You ran `dbt build --target prod` locally with ADC. | Local dev shouldn't target prod — that's what the workflow is for. Re-run `dbt build` (no target = default `dev`) to fix local state; the prod workflow will overwrite. |

## After this is set up

The day-to-day flow becomes:
1. **Edit models locally**, `dbt build` → `dev`
2. **Open a PR** → `ci` validates without touching `dev`/`staging`/`prod`
3. **Merge** → staging auto-deploys
4. **Click "Run workflow"** on the prod workflow to promote — your one-button "yes,
   ship it to prod"

Phase 9 makes that button require an approval. Phase 11 splits the project so each env
lives in its own GCP project (the crypto-pipeline pattern).
