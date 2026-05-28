# 11 — Terraform: Infra-as-code (Phase 10)

Phases 2–9 click-opped (or scripted) GCS buckets, BigQuery datasets, service accounts,
IAM bindings, the budget alert, and 12 enabled APIs. **Phase 10 puts all of that into
Terraform** so a future-you (or a forker) can `terraform apply` and reproduce the GCP
side from scratch.

## What's in Terraform (and what isn't)

**In Terraform** (`terraform/main.tf`):
- 12 APIs (`google_project_service`)
- 2 GCS buckets — `spotify-raw` (versioned) + `ci-state`
- 5 BigQuery datasets — `spotify_raw` + `spotify_analytics_{dev,ci,staging,prod}`
- 3 service accounts — `spotify-ingest-fn`, `spotify-scheduler`, `dbt-ci`
- Project-level IAM (BQ jobUser + dataEditor on the SAs that need it)
- Bucket-level IAM (objectAdmin)
- 1 billing budget alert (~$5)

**NOT in Terraform** (kept as application code or sensitive ops):
- The Cloud Function code + Cloud Run service → `deploy.sh` (the function source is
  app code, not infra)
- The Cloud Scheduler job → `deploy.sh` (depends on the function URL, easier to deploy
  alongside the function)
- The `dbt-ci` SA key JSON → `setup-ci.sh` (sensitive; never in state)
- GitHub Environment (`production`) + repo secrets → `setup-prod-gate.sh` + `setup-ci.sh`
  (GitHub-side, not GCP)

This is the standard real-world split: Terraform owns the durable infra; deploy
scripts own the code shipments and the GitHub-side glue.

## Heads up: Phase 10 keeps local state

Discipline (per JOURNEY): **local state for now**. Phase 11 moves it to a versioned GCS
bucket alongside the per-env-project refactor.

Practically this means `terraform.tfstate` lives at `terraform/terraform.tfstate` on
your laptop, gitignored. If you lose it, you re-import (see below). Forkers will
import their own brand-new state on first apply.

## Heads up: Terraform 1.6.0 + Google provider 5.x

The combo hits an `openpgp: key expired` error during `terraform init`. Use Terraform
**1.9.8** instead (the version this repo standardizes on). `setup-tools.sh` (not in
this repo) or manual install will fix it:

```bash
curl -sSL -o tf.zip https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
mkdir -p ~/bin && unzip -oq tf.zip terraform -d ~/bin && rm tf.zip
export PATH="$HOME/bin:$PATH"
```

## Heads up: `billingbudgets` API needs `user_project_override`

`google_billing_budget` reads via the billingbudgets API, which rejects ADC requests
without an explicit billing project. The provider block sets:
```hcl
provider "google" {
  billing_project       = var.project_id
  user_project_override = true
}
```
Without these, you get `403 SERVICE_DISABLED` with a misleading message even when the
API is enabled on your project.

## Prerequisites

- Terraform 1.9.8+ on `PATH`
- ADC alive (`gcloud auth application-default print-access-token > /dev/null`)
- Phase 2–9 already provisioned the actual resources (we're importing them)

## Fast path (first run — existing resources to import)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set project_id and billing_account_id

terraform init
./import.sh
terraform plan         # expected: a small "labels" diff
terraform apply -auto-approve
terraform plan         # expected: "No changes"
```

## Fast path (clean reproducer — no existing state)

If you're forking and starting from a brand-new GCP project, skip `import.sh` and just:

```bash
terraform init
terraform plan         # full create plan
terraform apply -auto-approve
```

You'll then need to:
1. Run `./setup-ci.sh` from the repo root to mint the dbt-ci SA key + upload GitHub
   secrets (Phase 6)
2. Run `./setup-prod-gate.sh` to create the GitHub Environment (Phase 9)
3. Run `./deploy.sh` to ship the Cloud Function + Scheduler (Phase 3)

## What `import.sh` does

For each resource that already exists in GCP, runs `terraform import <addr> <id>`,
**only if not already in state** (`terraform state list | grep -Fxq` guard). So you
can re-run it after any failure.

A typical first run imports ~30 resources in ~2 minutes.

## After import: tiny label diff

The first `terraform apply` after import adds the `managed_by = "terraform"` labels
declared in `main.tf` but not present on the actual resources. That's the expected
"adoption" diff — nothing functional changes.

After this one apply, `terraform plan` should print `No changes. Your infrastructure
matches the configuration.`

## Modifying infra (the new way, Phase 10 onward)

Want to add a new dataset? Edit `local.datasets` in `main.tf`, run:
```bash
terraform plan       # preview
terraform apply      # apply
```

No more `bq mk` from the shell — that'd be drift the next `plan` flags.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Error: openpgp: key expired` on `init` | Old Terraform binary | Install 1.9.8 (see top) |
| `Error acquiring the state lock` | A previous TF process hung | `pgrep -fa terraform`, kill stale PIDs, then `terraform force-unlock <ID>` |
| `Resource already managed by Terraform` during import | The resource was imported in a previous pass | The script's guard should skip it; if you removed it with `terraform state rm`, just re-import |
| `403 SERVICE_DISABLED` on `google_billing_budget` | ADC needs an explicit billing project | `user_project_override = true` + `billing_project = var.project_id` in the provider block |
| `Plan: N to change` even after apply | You've drifted from Terraform (someone ran `gcloud` directly) | Choose one source of truth — either re-import (`terraform refresh` + `import`) or `terraform apply` to overwrite the drift |
| Lost local state | `terraform.tfstate` deleted/corrupted | Re-run `terraform init` + `./import.sh`; state rebuilds from the real GCP state |

## Phase 10 honest scope caveats

- **No remote state** — Phase 11 moves it to GCS.
- **No modules** — single `main.tf` is still readable at ~200 lines. Phase 11
  introduces modules when we split into per-env projects.
- **Function + Scheduler are still in `deploy.sh`** — could be in Terraform with
  `google_cloudfunctions2_function` + `google_cloud_scheduler_job`, but the function
  source-upload dance is enough of a wart that real teams often keep app-code deploys
  out of Terraform. We match that.
- **GitHub Environment is still in `setup-prod-gate.sh`** — the GitHub provider for
  Terraform exists but adds a new auth dimension (PAT or app); not worth the cost
  for one Environment.

## What's next (Phase 11)

Refactor `main.tf` into `modules/data-project/` + `envs/{dev,staging,prod,infra}/`
with **per-env GCP projects**. Move state to a versioned GCS bucket in the infra
project. Swap dbt-ci's SA key for Workload Identity Federation. The Big One.
