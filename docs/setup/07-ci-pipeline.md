# 07 — First CI: dbt tests on every PR (Phase 6)

You have a working pipeline (Phases 1–5). Now wire GitHub Actions to run **`dbt build`
on every PR** so syntax errors and failing tests are caught before they hit `main`.

## What you'll have when done

- A **`spotify_analytics_ci`** BigQuery dataset (separate from prod `spotify_analytics`)
- A **`dbt-ci`** service account with **project-level** IAM (see "Two Phase 6 tradeoffs"
  below for why not dataset-scoped):
  - `roles/bigquery.jobUser` on the project (can run queries)
  - `roles/bigquery.dataEditor` on the project (read sources, write to any dataset)
- A JSON key for that SA stored as the **`GCP_SA_KEY`** GitHub repo secret
- The project id stored as **`GCP_PROJECT`** GitHub repo secret
- A **`.github/workflows/dbt-ci.yml`** workflow that runs `dbt build --target ci` on
  PRs touching `dbt/**`
- A green check on PRs that means "your changes parse + compile + pass tests"

## Two Phase 6 tradeoffs (known technical debt)

### 1. SA key JSON in a GitHub Secret

Level-1 real-world pattern:
- Long-lived credential, manual rotation
- Anyone with repo admin (or who exfiltrates the secret) gets the key

**Phase 11 (Level 3)** replaces this with **Workload Identity Federation** — GitHub's
OIDC token impersonates the SA without a key file.

### 2. Project-level IAM (not dataset-scoped)

The CI SA gets `bigquery.dataEditor` at the **project** level — it can read AND write
*any* BigQuery dataset in the project, including prod `spotify_analytics`. Ideally it'd
have `dataViewer` only on `spotify_raw` and `dataEditor` only on `spotify_analytics_ci`.

Why we don't: `bq add-iam-policy-binding` needs allowlisting and
`gcloud alpha bq datasets add-iam-policy-binding` needs an alpha component install.
Both are operator friction we're deferring.

The mitigation today is the workflow itself — it always runs `dbt build --target ci`,
which only writes to `spotify_analytics_ci`. A rogue PR could in theory change the
target to `dev`/prod and write garbage — that's the real Level-1 gap.

**Phase 7 (multi-env via dataset suffix)** and **Phase 11 (per-env GCP projects)** both
narrow this — by Phase 11 the CI SA lives in the dev project and can't reach prod at all.

## Prerequisites

- Doc 06 ran successfully (you've built dbt locally and have a working
  `spotify_analytics`)
- The `gh` CLI is authenticated against your fork (`gh auth status`)
- You're an admin on the repo (needed to set secrets)

## Fast path

```bash
set -a && source .env && set +a
./setup-ci.sh
```

`setup-ci.sh` is idempotent — re-run any time to refresh IAM or re-mint the key
(rotation).

## What `setup-ci.sh` does (6 steps)

1. **Create the CI dataset** `spotify_analytics_ci` (US, separate from prod)
2. **Create the `dbt-ci` SA** (with the propagation wait pattern from Phase 3)
3. **Grant IAM**: `bigquery.jobUser` on project, `dataViewer` on `spotify_raw`,
   `dataEditor` on `spotify_analytics_ci`
4. **Mint a JSON key** to a `mktemp` path (600 perms)
5. **Upload to GitHub secrets**: `GCP_SA_KEY` (the JSON), `GCP_PROJECT` (your project id)
6. **Delete the local key file** (`shred -u`)

## The workflow itself

`.github/workflows/dbt-ci.yml` triggers on PRs that touch `dbt/**`,
`requirements-dbt.txt`, or the workflow file. Steps:
1. Checkout
2. Set up Python 3.11 with pip cache
3. `pip install -r requirements-dbt.txt`
4. Write `secrets.GCP_SA_KEY` to `$RUNNER_TEMP/sa-key.json` (umask 077, outside workspace)
5. Export `GOOGLE_APPLICATION_CREDENTIALS=$RUNNER_TEMP/sa-key.json` and
   `DBT_PROFILES_DIR` so dbt finds both
6. `dbt build --target ci`

The `ci` target in `dbt/profiles.yml` uses `method: oauth` — dbt picks up the SA
identity via `GOOGLE_APPLICATION_CREDENTIALS` (same as ADC locally), but with a
service-account identity instead of your user.

## Verify

Open a no-op PR touching `dbt/`:

```bash
git checkout -b ci/smoke-test
echo "-- ci smoke test" >> dbt/models/staging/stg_top_tracks.sql
git add dbt/models/staging/stg_top_tracks.sql
git commit -m "Smoke test: ensure CI runs"
git push -u origin ci/smoke-test
gh pr create --fill
gh pr checks $(gh pr list --head ci/smoke-test --json number --jq '.[0].number')
```

Expected: `dbt CI / dbt-test` shows ✅ within ~2 minutes. Close + delete the smoke-test
PR after.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Workflow doesn't run on the PR | Paths filter didn't match. | Confirm the PR changes `dbt/**`, `requirements-dbt.txt`, or the workflow file. |
| `GCP_SA_KEY` secret missing | `setup-ci.sh` Step 5 failed. | `gh secret list --repo $GITHUB_REPO` to check; re-run the script. |
| `permission 'bigquery.jobs.create' denied` | IAM not yet propagated, or `bigquery.jobUser` binding missing. | Wait 30s, re-run; or re-run `setup-ci.sh`. |
| `Not found: Dataset spotify_analytics_ci` | Dataset wasn't created. | Re-run `setup-ci.sh` step 1. |
| `dbt build` succeeds locally but fails in CI | Differences usually due to the CI dataset starting empty. | Confirm the workflow runs `dbt build` not `dbt run` — `build` includes seed/snapshot/test pre-reqs. |
| `Error: Process completed with exit code 1` and no detail | dbt's error is usually a few lines up in the job log. | Click "View job logs" → scroll past the dbt log header. |

## Rotation

Phase 6 keys are long-lived — rotate manually:
```bash
gcloud iam service-accounts keys list --iam-account=dbt-ci@$GCP_PROJECT.iam.gserviceaccount.com
gcloud iam service-accounts keys delete <KEY_ID> --iam-account=dbt-ci@$GCP_PROJECT.iam.gserviceaccount.com
./setup-ci.sh    # mints a new key + uploads to GitHub secrets
```

Phase 11 makes this unnecessary by switching to WIF (no keys to rotate).

## What's NOT in Phase 6 (deferred)

- **No Slim CI** — every PR rebuilds every model. With 2 models that's fine. Phase 8
  adds `state:modified.body+ --defer`.
- **No per-PR schemas** — every PR writes to the same `spotify_analytics_ci`, last
  one wins. Phase 8 adds `dbt_ci_pr_<n>` ephemeral schemas.
- **No deployment** — CI just validates. Staging deploys come in Phase 7, prod-gate
  in Phase 9.
- **No WIF** — long-lived SA key. Phase 11.
