#!/usr/bin/env bash
# Phase 11: env-aware Cloud Function deploy.
# Usage:
#   ENV=staging PROJECT_ID=spotify-pipeline-stg-260529 ./deploy.sh
#   ENV=prod    PROJECT_ID=spotify-pipeline-prod-260529 ./deploy.sh
#
# Discipline:
#   - dev: NO function deploy (local-only ingestion)
#   - staging: function deployed, scheduler PAUSED (operator-triggered)
#   - prod: function deployed, scheduler ENABLED at 00:05 UTC daily
#
# Required env vars (load via `.env`):
#   ENV               staging | prod
#   PROJECT_ID        env's GCP project id
#   SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET
#
# Optional:
#   REGION            (default us-central1)
#   TIMEOUT           (default 300s)
#   MEMORY            (default 256Mi)

set -euo pipefail

ENV="${ENV:?Set ENV (staging | prod)}"
case "$ENV" in
    staging|prod) ;;
    dev)
        echo "Dev runs ingestion locally — no function deploy. Use: python snapshot.py"
        exit 0
        ;;
    *)  echo "Unknown ENV='$ENV'. Use staging or prod."; exit 1 ;;
esac

PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID to the env GCP project}"
: "${SPOTIFY_CLIENT_ID:?Set SPOTIFY_CLIENT_ID}"
: "${SPOTIFY_CLIENT_SECRET:?Set SPOTIFY_CLIENT_SECRET}"

REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-spotify-snapshot}"
SCHEDULER_JOB="${SCHEDULER_JOB:-spotify-snapshot-daily}"
TIMEOUT="${TIMEOUT:-300s}"
MEMORY="${MEMORY:-256Mi}"

case "$ENV" in
    staging) SCHEDULE="0 0 * * *" ; SCHEDULE_STATE="PAUSED"  ;;
    prod)    SCHEDULE="5 0 * * *" ; SCHEDULE_STATE="ENABLED" ;;
esac

INGEST_SA="spotify-ingest-fn@${PROJECT_ID}.iam.gserviceaccount.com"
SCHEDULER_SA="spotify-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=== Deploy to ${PROJECT_ID} (env=${ENV}, schedule=${SCHEDULE} state=${SCHEDULE_STATE}) ==="

# SAs are created by Terraform; just verify they exist.
gcloud iam service-accounts describe "$INGEST_SA"    --project="$PROJECT_ID" >/dev/null
gcloud iam service-accounts describe "$SCHEDULER_SA" --project="$PROJECT_ID" >/dev/null

echo "--- deploy function (gen2) ---"
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

echo "--- grant scheduler SA: run.invoker on the function ---"
gcloud run services add-iam-policy-binding "$FUNCTION_NAME" \
    --project="$PROJECT_ID" --region="$REGION" \
    --member="serviceAccount:${SCHEDULER_SA}" \
    --role="roles/run.invoker" > /dev/null

echo "  (waiting 30s for IAM propagation)"
sleep 30

echo "--- create / update scheduler job (state=${SCHEDULE_STATE}) ---"
if gcloud scheduler jobs describe "$SCHEDULER_JOB" \
    --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud scheduler jobs update http "$SCHEDULER_JOB" \
        --project="$PROJECT_ID" --location="$REGION" \
        --schedule="$SCHEDULE" \
        --uri="$FUNCTION_URL" \
        --http-method=POST \
        --oidc-service-account-email="$SCHEDULER_SA"
else
    gcloud scheduler jobs create http "$SCHEDULER_JOB" \
        --project="$PROJECT_ID" --location="$REGION" \
        --schedule="$SCHEDULE" \
        --uri="$FUNCTION_URL" \
        --http-method=POST \
        --oidc-service-account-email="$SCHEDULER_SA"
fi

# Apply requested state (PAUSED for staging, ENABLED for prod)
if [ "$SCHEDULE_STATE" = "PAUSED" ]; then
    gcloud scheduler jobs pause  "$SCHEDULER_JOB" --location="$REGION" --project="$PROJECT_ID" || true
else
    gcloud scheduler jobs resume "$SCHEDULER_JOB" --location="$REGION" --project="$PROJECT_ID" || true
fi

echo
echo "=== done ==="
echo "Function URL: ${FUNCTION_URL}"
echo "Scheduler:    ${SCHEDULER_JOB} (${SCHEDULE_STATE}, ${SCHEDULE})"
