# 13 — Terraform CI: plan-on-PR + apply-on-merge (Phase 12)

Phase 11 set up multi-env Terraform with remote state. Phase 12 wires that into
GitHub Actions: every PR touching `terraform/**` posts a plan comment per env;
merging to `main` applies per env.

## What you'll have when done

- A **`tf-runner`** SA in the infra project with:
  - `roles/editor` on all 4 projects (infra/dev/staging/prod)
  - `roles/resourcemanager.projectIamAdmin` on all 4 projects (lets Terraform manage
    project-level IAM bindings)
  - `roles/storage.objectAdmin` on the tfstate bucket
- WIF impersonation binding for `tf-runner` from the spotify-pipeline GitHub repo
- `.github/workflows/terraform-ci.yml` workflow that:
  - **PR**: matrix runs `terraform plan -lock=false` for `dev`/`staging`/`prod`/`infra`,
    posts (or updates) a single comment per env on the PR with the plan output
  - **merge to main**: matrix runs `terraform apply -auto-approve` for each env

## Why these IAM choices

`tf-runner` gets `editor` + `projectIamAdmin`:
- `editor` covers the bulk of resource management (buckets, datasets, SAs)
- **`projectIamAdmin`** is needed because `editor` does NOT include `setIamPolicy` on
  the project — without it, every `google_project_iam_member` resource fails
- Both bindings are scoped per project (cross-project IAM in infra/main.tf)
- The review/safety gate is at the **PR** level — humans read the plan comment before
  merging. There's no Environment-level approval on apply (the merge IS the approval).

`editor` is broad — anyone who compromises `tf-runner` can do anything inside the 4
projects. Mitigations:
- WIF attribute condition pins on `repository_id` — only THIS repo's OIDC tokens can
  impersonate it
- Plan-only on PR (`-lock=false` + no state changes)
- Apply-on-merge means main branch protection IS the audit trail

For more paranoid setups: split into `tf-plan-runner` (viewer + securityReviewer) and
`tf-apply-runner` (editor + iamAdmin), with apply gated by an Environment. Phase 12
keeps it simple.

## Prerequisites

- Phase 11 complete (`tf-runner` SA gets added in `terraform/envs/infra/main.tf`;
  `terraform apply` in `envs/infra/` provisions it)

## Fast path

After this PR merges:
1. The `terraform apply` job in this PR's workflow will fire on merge — that proves
   apply-on-merge works.
2. Future PRs touching `terraform/**` get a plan comment per env.

To verify locally:
```bash
cd terraform/envs/dev
terraform plan    # mirror of what CI runs
```

## How the comment is built

Per-env, the workflow:
1. Captures `terraform plan` output to `plan.txt` (last 60 KB to fit GitHub's comment limit)
2. Wraps in a `<details>` block with the env name + ✅/❌ status
3. Uses the actions-script API to either **update** an existing comment for this env
   (search by marker `**terraform plan: \`envs/<env>\`**`) or create a new one

This means consecutive pushes to a PR overwrite the previous plan comment — no
spam.

## Workflow structure

```yaml
on:
  pull_request: { paths: ['terraform/**', ...] }
  push:         { branches: [main], paths: ['terraform/**', ...] }

jobs:
  plan-or-apply:
    strategy:
      matrix:
        env: [dev, staging, prod, infra]
    steps:
      - checkout
      - hashicorp/setup-terraform@v3 (pinned to 1.9.8)
      - google-github-actions/auth@v2 with WIF → tf-runner
      - write terraform.tfvars (per-env, with the right project IDs)
      - terraform init
      - if PR: terraform plan -lock=false, capture output → output var
      - if merge: terraform apply -auto-approve
      - if PR: actions/github-script → upsert plan comment
```

Plans run with `-lock=false` so concurrent PRs don't block each other's plans (state
locks are *write* locks; plan is read-only).

## Repo-level Variables required

Set on the repo (not secrets — these are non-sensitive identifiers):
- `INFRA_PROJECT_ID`
- `DEV_PROJECT_ID`
- `STAGING_PROJECT_ID`
- `PROD_PROJECT_ID`
- `CI_STATE_BUCKET` (already set from Phase 11)

`scripts/setup-github-environments.sh` sets these.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Workflow fails immediately with `WIF_PROVIDER not set` | Repo secret missing | Re-run `scripts/setup-github-environments.sh` (Phase 11) |
| `Error: Error retrieving IAM policy for ... tf-runner: 404` on `terraform apply` | SA exists in config but not yet in GCP — race condition in Terraform | Add `depends_on = [google_service_account.tf_runner]` on the wif module (already in `infra/main.tf`) |
| Plan comment shows truncated output | GitHub comment limit (~65 KB) | The workflow already tails to last 60 KB; if you need more, switch to a separate file artifact |
| `roles/editor` insufficient for some resource | Some APIs need extra grants (e.g., `roles/iam.serviceAccountAdmin`) | Add the role to `tf_runner_iam_admin` or `tf_runner_editor` list in infra/main.tf and apply |
| Concurrent merges race on apply | Two merges to main land within seconds; Terraform state locks them | Acceptable — second merge waits ~30s, then succeeds |

## What's NOT in Phase 12 (deferred)

- **No apply gating** — merge IS the gate. Phase 13 could add an `infra-apply`
  Environment with required-reviewer if needed
- **No drift detection** — no scheduled `terraform plan` against `main` to catch
  out-of-band changes. Phase 13/14 could add this
- **No automatic rollback** — failed apply leaves partial state; you fix forward
