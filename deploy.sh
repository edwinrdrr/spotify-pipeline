#!/usr/bin/env bash
# Phase 3: deploy snapshot.py as a Cloud Function (gen2) + create a daily Cloud Scheduler.
# Idempotent — safe to re-run after partial failures or to update config.
#
# Required env vars (load via `.env`):
#   GCP_PROJECT, SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET
#
# Optional env vars (sensible defaults):
#   REGION         (default: us-central1)
#   FUNCTION_NAME  (default: spotify-snapshot)
#   SCHEDULER_JOB  (default: spotify-snapshot-daily)
#   SCHEDULE       (default: "5 0 * * *"  → 00:05 UTC daily)
#   TIMEOUT        (default: 300s)
#   MEMORY         (default: 256Mi)

set -euo pipefail

PROJECT_ID="${GCP_PROJECT:?Set GCP_PROJECT (your GCP project id)}"
: "${SPOTIFY_CLIENT_ID:?Set SPOTIFY_CLIENT_ID}"
: "${SPOTIFY_CLIENT_SECRET:?Set SPOTIFY_CLIENT_SECRET}"

REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-spotify-snapshot}"
SCHEDULER_JOB="${SCHEDULER_JOB:-spotify-snapshot-daily}"
SCHEDULE="${SCHEDULE:-5 0 * * *}"
TIMEOUT="${TIMEOUT:-300s}"
MEMORY="${MEMORY:-256Mi}"

INGEST_SA="spotify-ingest-fn@${PROJECT_ID}.iam.gserviceaccount.com"
SCHEDULER_SA="spotify-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET="${PROJECT_ID}-spotify-raw"

echo "=== Phase 3 deploy to ${PROJECT_ID} (${REGION}) ==="

echo "--- 1/6: create runtime SA (spotify-ingest-fn) ---"
gcloud iam service-accounts create spotify-ingest-fn \
    --project="$PROJECT_ID" \
    --display-name="Spotify ingest function runtime" 2>/dev/null \
    || echo "  (already exists)"

# SA creation takes ~5-15s to propagate before it can be used in IAM bindings.
# Poll until it shows up; bail after 60s.
echo "  (waiting for SA to propagate...)"
for attempt in $(seq 1 12); do
    if gcloud iam service-accounts describe "$INGEST_SA" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

echo "--- 2/6: grant runtime SA: storage + bigquery ---"
# objectAdmin (not objectCreator) — Creator can only create new objects; the function
# may overwrite same-day snapshots on re-runs, which requires delete permission.
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
    --member="serviceAccount:${INGEST_SA}" \
    --role="roles/storage.objectAdmin" > /dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${INGEST_SA}" \
    --role="roles/bigquery.jobUser" \
    --condition=None > /dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${INGEST_SA}" \
    --role="roles/bigquery.dataEditor" \
    --condition=None > /dev/null

echo "--- 3/6: create scheduler SA (spotify-scheduler) ---"
gcloud iam service-accounts create spotify-scheduler \
    --project="$PROJECT_ID" \
    --display-name="Cloud Scheduler -> Cloud Function invoker" 2>/dev/null \
    || echo "  (already exists)"

# Same propagation wait as the ingest SA.
echo "  (waiting for SA to propagate...)"
for attempt in $(seq 1 12); do
    if gcloud iam service-accounts describe "$SCHEDULER_SA" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

echo "--- 4/6: deploy function (gen2) ---"
# --set-env-vars is comma-separated; sensitive but acceptable for Phase 3 (Phase 5+
# moves these to Secret Manager). Quoted to handle any commas in secret (shouldn't be any).
gcloud functions deploy "$FUNCTION_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --gen2 \
    --runtime=python311 \
    --source=. \
    --entry-point=snapshot_http \
    --trigger-http \
    --no-allow-unauthenticated \
    --memory="$MEMORY" \
    --timeout="$TIMEOUT" \
    --service-account="$INGEST_SA" \
    --set-env-vars="SPOTIFY_CLIENT_ID=${SPOTIFY_CLIENT_ID},SPOTIFY_CLIENT_SECRET=${SPOTIFY_CLIENT_SECRET},GCP_PROJECT=${PROJECT_ID}"

FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
    --project="$PROJECT_ID" --region="$REGION" --gen2 \
    --format='value(serviceConfig.uri)')

echo "--- 5/6: grant scheduler SA: invoke the function (gen2 = Cloud Run under the hood) ---"
gcloud run services add-iam-policy-binding "$FUNCTION_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --member="serviceAccount:${SCHEDULER_SA}" \
    --role="roles/run.invoker" > /dev/null

# IAM binding takes ~30-60s to propagate. Without this wait, the first scheduled
# (or `jobs run`) invocation immediately after deploy hits 401.
echo "  (waiting 30s for run.invoker IAM to propagate; otherwise first trigger 401s)"
sleep 30

echo "--- 6/6: create / update scheduler job ---"
if gcloud scheduler jobs describe "$SCHEDULER_JOB" \
    --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud scheduler jobs update http "$SCHEDULER_JOB" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --schedule="$SCHEDULE" \
        --uri="$FUNCTION_URL" \
        --http-method=POST \
        --oidc-service-account-email="$SCHEDULER_SA"
else
    gcloud scheduler jobs create http "$SCHEDULER_JOB" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --schedule="$SCHEDULE" \
        --uri="$FUNCTION_URL" \
        --http-method=POST \
        --oidc-service-account-email="$SCHEDULER_SA"
fi

echo
echo "=== done ==="
echo "Function URL:    ${FUNCTION_URL}"
echo "Trigger now:     gcloud scheduler jobs run ${SCHEDULER_JOB} --location=${REGION} --project=${PROJECT_ID}"
echo "Next scheduled:  $(gcloud scheduler jobs describe ${SCHEDULER_JOB} --location=${REGION} --project=${PROJECT_ID} --format='value(scheduleTime)')"
