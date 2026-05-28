#!/usr/bin/env bash
# Phase 10: import the existing click-opped GCP resources into Terraform state
# so `terraform plan` shows zero changes.
#
# Idempotent: each import is gated by `terraform state list` so re-running is safe.
#
# Run from terraform/ directory after `terraform init`.

set -euo pipefail

if [ ! -f terraform.tfvars ]; then
    echo "Missing terraform.tfvars. Run: cp terraform.tfvars.example terraform.tfvars"
    echo "Then edit values for your project."
    exit 1
fi

PROJECT_ID=$(grep '^project_id' terraform.tfvars | awk -F= '{print $2}' | tr -d ' "')
BILLING_ID=$(grep '^billing_account_id' terraform.tfvars | awk -F= '{print $2}' | tr -d ' "')
echo "Importing into terraform state for project ${PROJECT_ID}..."

# Helper: import iff not already in state
tfimport() {
    local addr="$1"
    local id="$2"
    if terraform state list 2>/dev/null | grep -Fxq "$addr"; then
        echo "  ✓ already in state: $addr"
    else
        echo "  → importing $addr"
        terraform import "$addr" "$id"
    fi
}

# APIs ─────────────────────────────────────────────────────────────────────────
for api in storage bigquery cloudresourcemanager iam iamcredentials \
           billingbudgets cloudfunctions run cloudbuild artifactregistry \
           eventarc cloudscheduler; do
    tfimport "google_project_service.apis[\"${api}.googleapis.com\"]" \
             "${PROJECT_ID}/${api}.googleapis.com"
done

# Buckets ──────────────────────────────────────────────────────────────────────
tfimport "google_storage_bucket.spotify_raw" "${PROJECT_ID}-spotify-raw"
tfimport "google_storage_bucket.ci_state"    "${PROJECT_ID}-ci-state"

# Datasets ─────────────────────────────────────────────────────────────────────
for ds in spotify_raw spotify_analytics_dev spotify_analytics_ci \
          spotify_analytics_staging spotify_analytics_prod; do
    tfimport "google_bigquery_dataset.analytics[\"${ds}\"]" \
             "projects/${PROJECT_ID}/datasets/${ds}"
done

# Service accounts ─────────────────────────────────────────────────────────────
tfimport "google_service_account.ingest_fn" \
         "projects/${PROJECT_ID}/serviceAccounts/spotify-ingest-fn@${PROJECT_ID}.iam.gserviceaccount.com"
tfimport "google_service_account.scheduler" \
         "projects/${PROJECT_ID}/serviceAccounts/spotify-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
tfimport "google_service_account.dbt_ci" \
         "projects/${PROJECT_ID}/serviceAccounts/dbt-ci@${PROJECT_ID}.iam.gserviceaccount.com"

# IAM bindings ─────────────────────────────────────────────────────────────────
# bucket bindings: <bucket> <role> serviceAccount:<email>
tfimport "google_storage_bucket_iam_member.ingest_fn_bucket" \
         "b/${PROJECT_ID}-spotify-raw roles/storage.objectAdmin serviceAccount:spotify-ingest-fn@${PROJECT_ID}.iam.gserviceaccount.com"
tfimport "google_storage_bucket_iam_member.dbt_ci_ci_state" \
         "b/${PROJECT_ID}-ci-state roles/storage.objectAdmin serviceAccount:dbt-ci@${PROJECT_ID}.iam.gserviceaccount.com"

# project bindings: <project> <role> <member>
tfimport "google_project_iam_member.ingest_fn_bq_job" \
         "${PROJECT_ID} roles/bigquery.jobUser serviceAccount:spotify-ingest-fn@${PROJECT_ID}.iam.gserviceaccount.com"
tfimport "google_project_iam_member.ingest_fn_bq_data" \
         "${PROJECT_ID} roles/bigquery.dataEditor serviceAccount:spotify-ingest-fn@${PROJECT_ID}.iam.gserviceaccount.com"
tfimport "google_project_iam_member.dbt_ci_bq_job" \
         "${PROJECT_ID} roles/bigquery.jobUser serviceAccount:dbt-ci@${PROJECT_ID}.iam.gserviceaccount.com"
tfimport "google_project_iam_member.dbt_ci_bq_data" \
         "${PROJECT_ID} roles/bigquery.dataEditor serviceAccount:dbt-ci@${PROJECT_ID}.iam.gserviceaccount.com"

# Budget ───────────────────────────────────────────────────────────────────────
BUDGET_ID=$(gcloud billing budgets list \
    --billing-account="$BILLING_ID" \
    --filter="displayName=\"${PROJECT_ID} (~\$5)\"" \
    --format='value(name.basename())' 2>/dev/null | head -1)
if [ -n "$BUDGET_ID" ]; then
    tfimport "google_billing_budget.five_dollars" \
             "billingAccounts/${BILLING_ID}/budgets/${BUDGET_ID}"
else
    echo "  (no matching budget found — will be created by apply)"
fi

echo
echo "Done. Next:"
echo "  terraform plan"
echo "  → expected: 'No changes' or a tiny config diff (e.g. labels)"
