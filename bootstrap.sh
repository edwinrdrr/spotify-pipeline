#!/usr/bin/env bash
# Phase 11: multi-project bootstrap.
# Creates 4 GCP projects (infra/dev/stg/prod), links billing, enables APIs,
# creates the tfstate bucket, then applies Terraform per env.
#
# Idempotent — safe to re-run after partial failures.
#
# Required env vars:
#   BILLING_ACCOUNT_ID
#
# Optional env vars:
#   PROJECT_SUFFIX   (default: 260529)
#   GITHUB_REPO      (default: edwinrdrr/spotify-pipeline)
#   BUDGET_AMOUNT    (default: 80000 — IDR; pass 5USD etc. for other currencies)

set -euo pipefail

BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID:?Set BILLING_ACCOUNT_ID — gcloud billing accounts list}"
PROJECT_SUFFIX="${PROJECT_SUFFIX:-260529}"
GITHUB_REPO="${GITHUB_REPO:-edwinrdrr/spotify-pipeline}"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-80000}"

INFRA="spotify-pipeline-infra-${PROJECT_SUFFIX}"
DEV="spotify-pipeline-dev-${PROJECT_SUFFIX}"
STG="spotify-pipeline-stg-${PROJECT_SUFFIX}"
PROD="spotify-pipeline-prod-${PROJECT_SUFFIX}"
TFSTATE_BUCKET="${INFRA}-tfstate"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${REPO_DIR}/terraform"

echo "=== Phase 11 bootstrap (suffix ${PROJECT_SUFFIX}) ==="

create_project() {
    local p="$1"
    if gcloud projects describe "$p" >/dev/null 2>&1; then
        echo "  ✓ $p exists"
    else
        gcloud projects create "$p" --name="$(echo "$p" | cut -d- -f1-3)" 2>&1
    fi
    # link billing if not already
    if gcloud billing projects describe "$p" --format='value(billingEnabled)' 2>/dev/null | grep -q True; then
        echo "  ✓ $p billing linked"
    else
        gcloud billing projects link "$p" --billing-account="$BILLING_ACCOUNT_ID" >/dev/null
        echo "  + $p billing linked"
    fi
}

echo "--- 1/8: create 4 projects ---"
create_project "$INFRA"
create_project "$DEV"
create_project "$STG"
create_project "$PROD"

echo "--- 2/8: ADC quota project -> infra ---"
gcloud config set project "$INFRA" 2>&1 | tail -1
gcloud auth application-default set-quota-project "$INFRA" 2>&1 | tail -1

echo "--- 3/8: enable APIs (base on all, function on staging/prod, infra extras on infra) ---"
BASE_APIS="storage.googleapis.com bigquery.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com iamcredentials.googleapis.com"
FUNCTION_APIS="cloudfunctions.googleapis.com run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com eventarc.googleapis.com cloudscheduler.googleapis.com"
INFRA_APIS="sts.googleapis.com billingbudgets.googleapis.com"
gcloud services enable $BASE_APIS $INFRA_APIS --project="$INFRA" >/dev/null
gcloud services enable $BASE_APIS               --project="$DEV"   >/dev/null
gcloud services enable $BASE_APIS $FUNCTION_APIS --project="$STG"  >/dev/null
gcloud services enable $BASE_APIS $FUNCTION_APIS --project="$PROD" >/dev/null
echo "  apis enabled"

echo "--- 4/8: per-project budget alerts (~\$5) ---"
for p in "$INFRA" "$DEV" "$STG" "$PROD"; do
    if gcloud billing budgets list --billing-account="$BILLING_ACCOUNT_ID" \
            --filter="displayName=\"${p} (~\$5)\"" --format='value(name)' 2>/dev/null | grep -q .; then
        echo "  ✓ $p budget exists"
    else
        PN=$(gcloud projects describe "$p" --format='value(projectNumber)')
        gcloud billing budgets create \
            --billing-account="$BILLING_ACCOUNT_ID" \
            --display-name="${p} (~\$5)" \
            --budget-amount="$BUDGET_AMOUNT" \
            --threshold-rule=percent=0.5 \
            --threshold-rule=percent=0.9 \
            --threshold-rule=percent=1.0 \
            --filter-projects="projects/${PN}" >/dev/null
        echo "  + $p budget created"
    fi
done

echo "--- 5/8: tfstate bucket (versioned) in infra ---"
if gcloud storage buckets describe "gs://${TFSTATE_BUCKET}" >/dev/null 2>&1; then
    echo "  ✓ gs://${TFSTATE_BUCKET} exists"
else
    gcloud storage buckets create "gs://${TFSTATE_BUCKET}" \
        --project="$INFRA" --location=US --uniform-bucket-level-access >/dev/null
    gcloud storage buckets update "gs://${TFSTATE_BUCKET}" --versioning >/dev/null
    echo "  + gs://${TFSTATE_BUCKET} created"
fi

echo "--- 6/8: write terraform.tfvars per env ---"
for env in dev staging prod; do
    case "$env" in
        dev)     PID="$DEV"  ;;
        staging) PID="$STG"  ;;
        prod)    PID="$PROD" ;;
    esac
    cat > "${TF_DIR}/envs/${env}/terraform.tfvars" <<EOF
project_id = "${PID}"
EOF
done

REPO_ID=$(gh api "repos/${GITHUB_REPO}" --jq .id)
cat > "${TF_DIR}/envs/infra/terraform.tfvars" <<EOF
project_id           = "${INFRA}"
dev_project_id       = "${DEV}"
staging_project_id   = "${STG}"
prod_project_id      = "${PROD}"
github_repository    = "${GITHUB_REPO}"
github_repository_id = "${REPO_ID}"
EOF
echo "  tfvars written (github_repository_id=${REPO_ID})"

echo "--- 7/8: apply env data projects (dev, staging, prod) ---"
for env in dev staging prod; do
    echo "  > envs/${env}"
    ( cd "${TF_DIR}/envs/${env}" \
      && terraform init -input=false -upgrade >/dev/null \
      && terraform apply -auto-approve -input=false )
done

echo "--- 8/8: apply infra LAST (creates WIF + binds env SAs) ---"
cd "${TF_DIR}/envs/infra"
terraform init -input=false -upgrade >/dev/null
# Import tfstate bucket on first apply (it was created out-of-band).
if ! terraform state list 2>/dev/null | grep -Fxq 'google_storage_bucket.tfstate'; then
    terraform import google_storage_bucket.tfstate "$TFSTATE_BUCKET"
fi
terraform apply -auto-approve -input=false

echo
echo "=== done ==="
echo "WIF provider (set this as a repo-level GitHub Secret WIF_PROVIDER):"
terraform output -raw wif_provider_name
echo
echo "Next: ./scripts/setup-github-environments.sh"
