#!/usr/bin/env bash
# Phase 9: configure the `production` GitHub Environment with a required-reviewer
# rule so the prod workflow pauses for approval before it runs.
#
# Idempotent — safe to re-run.
#
# Required:
#   gh authenticated as a repo admin
#
# Optional env vars:
#   GITHUB_REPO   (default: edwinrdrr/spotify-pipeline)
#   REVIEWER      (default: the gh-authenticated user)

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-edwinrdrr/spotify-pipeline}"
REVIEWER="${REVIEWER:-$(gh api user --jq .login)}"
USER_ID=$(gh api "users/${REVIEWER}" --jq .id)

echo "=== Phase 9 prod-gate for ${GITHUB_REPO} ==="
echo "  reviewer:  ${REVIEWER}  (id=${USER_ID})"
echo

# wait_timer=0           — no enforced delay
# prevent_self_review=false  — solo: you both deploy and approve
# reviewers=[YOU]        — only you can approve prod runs
printf '{"wait_timer":0,"prevent_self_review":false,"reviewers":[{"type":"User","id":%s}]}' \
    "${USER_ID}" \
    | gh api -X PUT "repos/${GITHUB_REPO}/environments/production" --input - > /dev/null

echo "production environment configured."
echo
echo "Verify:"
gh api "repos/${GITHUB_REPO}/environments/production" \
    --jq '"  required reviewer: " + (.protection_rules[] | select(.type=="required_reviewers") | .reviewers[0].reviewer.login) + " (wait_timer=" + (.protection_rules[] | select(.type=="wait_timer") | .wait_timer | tostring) + ")"'

echo
echo "Next merge to main touching dbt/** will fire dbt-deploy-prod.yml and pause"
echo "for your approval. Approve at: Actions tab -> the run -> 'Review deployments'."
