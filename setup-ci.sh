#!/usr/bin/env bash
# Phase 6: provision the CI-side GCP plumbing.
# Idempotent — safe to re-run.
#
# What it does:
#   1. Create a dedicated `spotify_analytics_ci` BigQuery dataset (CI writes here)
#   2. Create a `dbt-ci` service account
#   3. Grant the SA: jobUser on the project, dataViewer on spotify_raw,
#      dataEditor on spotify_analytics_ci
#   4. Mint a JSON key for the SA (one-time; stored in /tmp briefly)
#   5. Upload the key + project id to GitHub repo secrets via `gh`
#   6. Delete the local key file
#
# Required env vars (load via `.env`):
#   GCP_PROJECT — your project id
#
# Required tools:
#   gcloud, bq, gh (logged in to the repo's owner)

set -euo pipefail

PROJECT_ID="${GCP_PROJECT:?Set GCP_PROJECT}"
GITHUB_REPO="${GITHUB_REPO:-edwinrdrr/spotify-pipeline}"
SA_NAME="dbt-ci"
SA="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=== Phase 6 CI setup for ${PROJECT_ID} (repo: ${GITHUB_REPO}) ==="

echo "--- 1/6: create spotify_analytics_ci dataset + ci-state bucket ---"
if bq --project_id="$PROJECT_ID" ls --format=prettyjson 2>/dev/null \
        | grep -q '"spotify_analytics_ci"'; then
    echo "  spotify_analytics_ci dataset: already exists"
else
    bq --project_id="$PROJECT_ID" mk --dataset --location=US spotify_analytics_ci
fi

# Phase 8: ci-state bucket holds the prod dbt manifest for Slim CI deferral.
CI_STATE_BUCKET="${PROJECT_ID}-ci-state"
if gcloud storage buckets describe "gs://${CI_STATE_BUCKET}" >/dev/null 2>&1; then
    echo "  gs://${CI_STATE_BUCKET}: already exists"
else
    gcloud storage buckets create "gs://${CI_STATE_BUCKET}" \
        --project="$PROJECT_ID" \
        --location=US \
        --uniform-bucket-level-access > /dev/null
    echo "  gs://${CI_STATE_BUCKET}: created"
fi

echo "--- 2/6: create dbt-ci service account ---"
gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="dbt CI runner (Phase 6 — Level 1)" 2>/dev/null \
    || echo "  (already exists)"

echo "  (waiting for SA to propagate before binding IAM...)"
for attempt in $(seq 1 12); do
    if gcloud iam service-accounts describe "$SA" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

echo "--- 3/6: grant IAM (project-level — Phase 6 / Level 1 tradeoff) ---"
# Project-level: jobUser (run dbt queries) + dataEditor (read sources, write to CI dataset).
#
# Ideal scoping would be dataset-level: dataViewer on spotify_raw + dataEditor on
# spotify_analytics_ci. But `bq add-iam-policy-binding` requires allowlisting and
# `gcloud alpha bq datasets add-iam-policy-binding` requires installing the alpha
# component group, which adds operator friction. Project-level grants are the honest
# Level-1 tradeoff: CI SA can theoretically touch prod spotify_analytics. Phase 7
# (multi-env via dataset suffix) and Phase 11 (per-project isolation) fix this.
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" \
    --role="roles/bigquery.jobUser" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" \
    --role="roles/bigquery.dataEditor" \
    --condition=None > /dev/null

# Phase 8: grant storage.objectAdmin on the ci-state bucket so the prod workflow
# can republish the manifest and CI runs can fetch it.
gcloud storage buckets add-iam-policy-binding "gs://${CI_STATE_BUCKET}" \
    --member="serviceAccount:${SA}" \
    --role="roles/storage.objectAdmin" > /dev/null

echo "--- 4/6: mint a JSON key for the SA ---"
KEY_PATH="$(mktemp -t dbt-ci-key.XXXXXX.json)"
chmod 600 "$KEY_PATH"
gcloud iam service-accounts keys create "$KEY_PATH" \
    --iam-account="$SA" \
    --project="$PROJECT_ID" > /dev/null
echo "  written to: $KEY_PATH"

echo "--- 5/6: upload to GitHub repo secrets ---"
gh secret set GCP_SA_KEY  --repo="$GITHUB_REPO" < "$KEY_PATH"
gh secret set GCP_PROJECT --repo="$GITHUB_REPO" --body "$PROJECT_ID"
echo "  GCP_SA_KEY and GCP_PROJECT set as repo secrets"

echo "--- 6/6: delete the local key file ---"
shred -u "$KEY_PATH" 2>/dev/null || rm -f "$KEY_PATH"
echo "  $KEY_PATH removed"

echo
echo "=== done ==="
echo "Open a PR touching dbt/** and the .github/workflows/dbt-ci.yml workflow will run."
echo
echo "To rotate the key later (Phase 11 will replace this with WIF):"
echo "  gcloud iam service-accounts keys list --iam-account=$SA"
echo "  gcloud iam service-accounts keys delete <KEY_ID> --iam-account=$SA"
echo "  then re-run this script."
