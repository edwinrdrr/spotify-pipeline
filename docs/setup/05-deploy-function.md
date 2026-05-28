# 05 — Deploy snapshot as a Cloud Function + daily scheduler

You've verified `snapshot.py` works against your project (doc 04). Now wrap it as a
**Cloud Function gen2** (HTTP-triggered) and create a **Cloud Scheduler** job that
hits it daily. Your laptop becomes optional.

## What you'll have when done

- A Cloud Function `spotify-snapshot` in `us-central1` (override with `REGION`)
- Two purpose-built service accounts:
  - `spotify-ingest-fn@<project>` — the function runtime; can write to your bucket
    and to BigQuery, can't do anything else
  - `spotify-scheduler@<project>` — invokes the function via OIDC, can't do anything
    else
- A Cloud Scheduler job `spotify-snapshot-daily` firing at `00:05 UTC` (override
  with `SCHEDULE`)
- The function URL stored in your gcloud config (you'll see it in deploy output)

## Why two SAs (not one)?

- **Principle of least privilege**: the function reads/writes data; the scheduler just
  signs an OIDC token and invokes. Different jobs, different identities.
- **Audit clarity**: BQ load jobs are attributed to `spotify-ingest-fn`; scheduler
  invocations are attributed to `spotify-scheduler`. If a write goes wrong, you know
  which identity did it.
- **Real-world pattern**: this is what crypto-pipeline does at scale (`crypto-ingest-fn`
  + `crypto-scheduler`). Same shape, smaller.

## Heads up: env-var secrets

Phase 3 ships `SPOTIFY_CLIENT_SECRET` to the function via `--set-env-vars`. It's then
visible in `gcloud functions describe`, in the Cloud Function console, and to anyone
with `roles/viewer` on the project. **This is intentionally simple for Phase 3** —
Phase 5+ moves secrets to Secret Manager. For now: don't grant `viewer` to anyone you
wouldn't share the secret with.

## Prerequisites

- Doc 04 ran successfully (local snapshot landed in BQ)
- Doc 03 step 5 enabled the function/scheduler APIs (`cloudfunctions`, `run`,
  `cloudbuild`, `artifactregistry`, `eventarc`, `cloudscheduler`, `iam`,
  `iamcredentials`). If you set up the project before this doc existed, re-run
  step 5 — `gcloud services enable` is idempotent.

## Fast path

```bash
set -a && source .env && set +a
./deploy.sh
```

`deploy.sh` is idempotent — re-run it any time to update the function code, the
scheduler cron, or the environment variables.

## What `deploy.sh` does (6 phases)

1. **Create runtime SA** `spotify-ingest-fn` (if not already)
2. **Grant runtime SA IAM**:
   - `roles/storage.objectCreator` on `gs://<project>-spotify-raw`
   - `roles/bigquery.jobUser` + `roles/bigquery.dataEditor` on the project
3. **Create scheduler SA** `spotify-scheduler`
4. **Deploy function** (gen2):
   - Source: `.` (excluded files in `.gcloudignore`)
   - Entry point: `snapshot_http` in `main.py`
   - Runtime SA: `spotify-ingest-fn`
   - Env vars: `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, `GCP_PROJECT`
   - `--no-allow-unauthenticated` (only invokable via OIDC from the scheduler SA)
5. **Grant scheduler SA** `roles/run.invoker` on the function (gen2 = Cloud Run
   under the hood, so the invoker role lives on Cloud Run not Cloud Functions)
6. **Create / update scheduler job** `spotify-snapshot-daily`:
   - `--schedule="5 0 * * *"` (00:05 UTC daily)
   - `--http-method=POST` to the function URL
   - `--oidc-service-account-email=spotify-scheduler@...`

## Trigger immediately (don't wait until tomorrow)

```bash
gcloud scheduler jobs run spotify-snapshot-daily \
    --location=us-central1 --project="$GCP_PROJECT"
# wait ~10 seconds, then:
gcloud scheduler jobs describe spotify-snapshot-daily \
    --location=us-central1 --project="$GCP_PROJECT" \
    --format='value(status.code,lastAttemptTime,status.message)'
# → 0 (OK), recent timestamp, empty message
```

## Verify the function actually ran

```bash
# 1. function logs (last 10 lines)
gcloud functions logs read spotify-snapshot \
    --gen2 --region=us-central1 --project="$GCP_PROJECT" --limit=10

# 2. distinct snapshot dates — should grow by 1 after each successful run
bq query --use_legacy_sql=false --format=csv --quiet \
    "SELECT COUNT(DISTINCT snapshot_date) AS days
     FROM \`${GCP_PROJECT}.spotify_raw.top_tracks\`"

# 3. row count grows by ~50 per snapshot
bq query --use_legacy_sql=false --format=csv --quiet \
    "SELECT COUNT(*) FROM \`${GCP_PROJECT}.spotify_raw.top_tracks\`"
```

## Inspecting / pausing / unpausing

```bash
# inspect current schedule
gcloud scheduler jobs describe spotify-snapshot-daily \
    --location=us-central1 --project="$GCP_PROJECT" \
    --format='value(schedule,state,scheduleTime)'

# pause (no more daily runs)
gcloud scheduler jobs pause spotify-snapshot-daily \
    --location=us-central1 --project="$GCP_PROJECT"

# resume
gcloud scheduler jobs resume spotify-snapshot-daily \
    --location=us-central1 --project="$GCP_PROJECT"
```

> **Gotcha**: `gcloud scheduler jobs run` on a PAUSED job fails with
> `Job.state must be ENABLED`. Resume → run → pause if you want a one-shot during a
> pause window.

## Troubleshooting

| Error | What it means | Fix |
|---|---|---|
| Deploy stops at `Building...` for >5 min | First-time Cloud Build is slow; subsequent deploys cache. | Wait it out. ~3 min for first build, ~30 s for subsequent. |
| `Permission 'iam.serviceAccounts.actAs' denied` | Your user doesn't have `roles/iam.serviceAccountUser` on the runtime SA. | `gcloud iam service-accounts add-iam-policy-binding spotify-ingest-fn@... --member=user:YOU --role=roles/iam.serviceAccountUser` |
| `403 Forbidden` when scheduler triggers | scheduler SA wasn't granted `roles/run.invoker` on the function. | Re-run `deploy.sh` (step 5 sets it). |
| Function logs show `403 ... Permission 'storage.objects.create' denied` | runtime SA missing bucket write. | Re-run `deploy.sh` (step 2 sets it). |
| Function logs show `403 ... Permission 'bigquery.jobs.create' denied` | runtime SA missing BQ jobUser. | Re-run `deploy.sh` (step 2 sets it). |
| Function timed out | Default 300s should be enough; Spotify CDN 503-stormed past 63s. | Re-trigger manually; if persistent, bump `TIMEOUT` and the script's retry budget. |
| `Eventarc API has not been used` during deploy | doc 03 step 5 didn't enable `eventarc.googleapis.com`. | Run the consolidated `gcloud services enable` from doc 03 step 5. |

## All green?

```bash
# Did today's scheduled run land?
bq query --use_legacy_sql=false --format=pretty \
    "SELECT snapshot_date, COUNT(*) AS tracks
     FROM \`${GCP_PROJECT}.spotify_raw.top_tracks\`
     GROUP BY snapshot_date
     ORDER BY snapshot_date DESC LIMIT 5"
```

You should see one row per snapshot date, each with 50 tracks. **Your laptop is no
longer in the critical path** — Phase 3 closed.
