#!/usr/bin/env bash
# Phase 11: configure GitHub Environments + per-Environment secrets + required-reviewer.
# Idempotent.

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-edwinrdrr/spotify-pipeline}"
PROJECT_SUFFIX="${PROJECT_SUFFIX:-260529}"

DEV="spotify-pipeline-dev-${PROJECT_SUFFIX}"
STG="spotify-pipeline-stg-${PROJECT_SUFFIX}"
PROD="spotify-pipeline-prod-${PROJECT_SUFFIX}"
INFRA="spotify-pipeline-infra-${PROJECT_SUFFIX}"
CI_STATE_BUCKET="${INFRA}-ci-state"

USER_ID=$(gh api user --jq .id)

echo "=== Configuring GitHub Environments + secrets ==="

# dev / staging: no reviewer
echo '{"wait_timer":0}' | gh api -X PUT "repos/${GITHUB_REPO}/environments/dev"     --input - > /dev/null
echo '{"wait_timer":0}' | gh api -X PUT "repos/${GITHUB_REPO}/environments/staging" --input - > /dev/null

# production: required-reviewer = me, prevent_self_review=false
printf '{"wait_timer":0,"prevent_self_review":false,"reviewers":[{"type":"User","id":%s}]}' "$USER_ID" \
    | gh api -X PUT "repos/${GITHUB_REPO}/environments/production" --input - > /dev/null

echo "  Environments: dev, staging, production"

# Per-Environment secrets — each workflow's `environment:` declares which env, GitHub
# scopes secrets accordingly.
gh secret set GCP_PROJECT_DEV     --env dev        --repo="$GITHUB_REPO" --body "$DEV"
gh secret set GCP_PROJECT_STAGING --env staging    --repo="$GITHUB_REPO" --body "$STG"
gh secret set GCP_PROJECT_PROD    --env production --repo="$GITHUB_REPO" --body "$PROD"
echo "  per-env secrets: GCP_PROJECT_DEV/STAGING/PROD set"

# Repo-level: WIF_PROVIDER (same for all envs — points at infra)
# Read it from terraform output.
TF_INFRA="$(cd "$(dirname "$0")/.." && pwd)/terraform/envs/infra"
WIF_PROVIDER=$(cd "$TF_INFRA" && terraform output -raw wif_provider_name 2>/dev/null || true)
if [ -z "$WIF_PROVIDER" ]; then
    echo "  ! WIF_PROVIDER unavailable — run bootstrap.sh first, then re-run me"
    exit 1
fi
gh secret set WIF_PROVIDER --repo="$GITHUB_REPO" --body "$WIF_PROVIDER"
echo "  repo secret: WIF_PROVIDER = ${WIF_PROVIDER}"

# Repo-level variables: CI_STATE_BUCKET (Slim CI) + project IDs (terraform-ci.yml)
gh variable set CI_STATE_BUCKET    --repo="$GITHUB_REPO" --body "$CI_STATE_BUCKET"
gh variable set INFRA_PROJECT_ID   --repo="$GITHUB_REPO" --body "$INFRA"
gh variable set DEV_PROJECT_ID     --repo="$GITHUB_REPO" --body "$DEV"
gh variable set STAGING_PROJECT_ID --repo="$GITHUB_REPO" --body "$STG"
gh variable set PROD_PROJECT_ID    --repo="$GITHUB_REPO" --body "$PROD"
echo "  repo vars: CI_STATE_BUCKET + per-env project IDs"

# Remove legacy secrets from earlier phases
for s in GCP_SA_KEY GCP_PROJECT; do
    if gh secret list --repo="$GITHUB_REPO" 2>/dev/null | grep -q "^$s	"; then
        gh secret delete "$s" --repo="$GITHUB_REPO"
        echo "  - removed legacy repo secret: $s"
    fi
done

echo
echo "=== done ==="
