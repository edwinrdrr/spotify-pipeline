# 10 — Required-reviewer gate on prod (Phase 9)

Phase 7 had prod as a manual `workflow_dispatch` — anyone with repo-write could fire
it. Phase 9 adds a **GitHub Environment** called `production` with a **required-reviewer**
protection rule, and switches the prod workflow to also fire automatically on merge.
Now every merge that touches `dbt/**` queues a prod deploy that **pauses until
someone clicks Approve**.

## What you'll have when done

- A `production` GitHub Environment with **required-reviewer = you**
- `prevent_self_review = false` (solo: you both deploy and approve)
- `dbt-deploy-prod.yml` triggers on **push to `main` + `workflow_dispatch`** instead of dispatch-only
- The prod job declares `environment: production` — GitHub holds it in `waiting` until
  you approve in the Actions UI

The merge-to-main flow becomes:
```
merge PR to main
   ↓
[staging workflow] auto-runs (no gate)
[prod workflow]    queues, status = "waiting"
   ↓ you click Approve
[prod workflow]    runs
```

## Why this exists

Phase 7's prod-as-workflow-dispatch meant any repo-write could `gh workflow run`
straight to prod, including accidentally on the wrong branch. Phase 9 makes the
human-in-the-loop step explicit:
- You see *what* you're about to deploy (the run's commit + diff)
- You actively click Approve
- It's audited (the Environment events log records who approved when)

This is the real-world pattern: **two events** (the merge, and the approval) before
prod changes.

## Heads up: solo + `prevent_self_review`

GitHub's default for `prevent_self_review` is `false` for new Environments, but the
Web UI defaults to `true` when you set up via the browser. For a solo project, you
**must** keep it `false` — otherwise YOU can't approve your own deploy, and prod
runs sit in `waiting` forever. `setup-prod-gate.sh` sets it explicitly.

## Public-repo requirement

GitHub Environment protection rules (including required-reviewer) require:
- **Public repo** (free), OR
- Private repo + GitHub Pro / Team / Enterprise

This repo is public, so you're good.

## Prerequisites

- `gh` authenticated as a **repo admin** (you, on your own repo, qualifies)
- Phase 7 & 8 complete (prod workflow exists + republishes the manifest)

## Fast path

```bash
./setup-prod-gate.sh
```

Idempotent. Optional env vars:
- `GITHUB_REPO` (default `edwinrdrr/spotify-pipeline`)
- `REVIEWER` (default the gh-authenticated user)

## What `setup-prod-gate.sh` does

1. Look up the reviewer's numeric user id (`gh api users/<login> --jq .id`)
2. `PUT repos/<org>/<repo>/environments/production` with body:
   ```json
   {
     "wait_timer": 0,
     "prevent_self_review": false,
     "reviewers": [{"type": "User", "id": <YOU>}]
   }
   ```
3. Echo a `gh api ... --jq` verification

## Approving a prod deploy (after merge)

After a `dbt/**` PR merges, you'll see in the Actions tab:
```
✓ dbt deploy → staging        (running / success)
⏸ dbt deploy → prod           (waiting — required-reviewer approval)
```

**Via the UI:**
1. Click the prod run
2. Click **"Review deployments"** at the top
3. Tick `production`
4. Add an optional comment, click **Approve and deploy**

**Via the CLI:**
```bash
RUN=$(gh run list --workflow="dbt deploy → prod" --limit 1 --json databaseId --jq '.[0].databaseId')
PROD_ENV_ID=$(gh api repos/edwinrdrr/spotify-pipeline/environments/production --jq .id)
gh api -X POST "repos/edwinrdrr/spotify-pipeline/actions/runs/$RUN/pending_deployments" \
    -F "environment_ids[]=$PROD_ENV_ID" -f state=approved -f comment="ship it"
```

`state=rejected` instead of `approved` cancels the deploy.

## Verify the gate

After Phase 9 merges, the merge itself triggers `dbt-deploy-prod.yml`. Watch:
```bash
sleep 20
gh run list --branch main --workflow "dbt deploy → prod" --limit 1 \
    --json databaseId,status,conclusion
# expected: status="waiting" (gate is live)
```

Then approve via UI or CLI; the run will move to `in_progress` → `success`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Prod workflow runs immediately without pausing | `environment:` key not set on the job, or the Environment doesn't exist. | Confirm `dbt-deploy-prod.yml` has `environment: production`; re-run `setup-prod-gate.sh`. |
| "You cannot approve your own deployment" | `prevent_self_review: true` got set somehow (e.g., via the UI). | Re-run `setup-prod-gate.sh` — it explicitly sets `false`. |
| Approval UI shows no environments to approve | The workflow run isn't actually waiting on an Environment. | Check `gh run view <RUN> --json status` — must be `waiting`. If it's `completed` already, the gate didn't apply. |
| Approval succeeded but prod job still didn't start | Approval may have applied to a different run if you have multiple in flight. | `gh run list --workflow "dbt deploy → prod"` — find the right `databaseId`. |
| Setup script fails: `404 Not Found` on `gh api PUT environments/...` | Public-repo requirement: you're on a private repo without Pro/Team. | Make the repo public (or upgrade plan). |

## What's NOT in Phase 9 (deferred)

- **No wait-timer** — could add `wait_timer: 5` (minutes) to enforce a cooldown after
  approval before deploy. Phase 13 might add this if needed.
- **No Slack / email notifications** — Phase 13 wires alerting; today the notification
  is the GitHub "Review deployments" email/banner.
- **No per-Environment secrets** — Phase 11 (per-env GCP projects) will move
  `GCP_PROJECT` and `GCP_SA_KEY` to per-Environment scope so prod and staging use
  different SAs.
- **No `staging` Environment** — only `production` is gated. Staging stays
  push-to-main auto-deploy.
