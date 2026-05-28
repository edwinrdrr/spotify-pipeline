# Phase 10: Terraform-izes what we click-opped through Phases 2–9.
#
# Scope (in this file):
#   - APIs (google_project_service)
#   - 2 GCS buckets (spotify-raw, ci-state)
#   - 5 BigQuery datasets (spotify_raw + analytics_{dev,ci,staging,prod})
#   - 3 service accounts (spotify-ingest-fn, spotify-scheduler, dbt-ci)
#   - Project-level + bucket-level IAM
#   - 1 billing budget
#
# NOT in here (intentionally — application code + GitHub-side concerns):
#   - Cloud Function code + Cloud Run service  -> deploy.sh
#   - Cloud Scheduler job                       -> deploy.sh
#   - dbt-ci SA key                             -> setup-ci.sh (sensitive; never in state)
#   - GitHub Environment + repo secrets         -> setup-prod-gate.sh + setup-ci.sh
#
# Backend: local state for Phase 10 (Phase 11 moves it remote alongside per-env projects).

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # billing-related APIs need an explicit billing project on ADC.
  billing_project       = var.project_id
  user_project_override = true
}

# ──────────────────────────────────────────────────────────────────────────────
# APIs
# ──────────────────────────────────────────────────────────────────────────────

locals {
  apis = [
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
    "cloudscheduler.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false # leave APIs enabled if we ever destroy
}

# ──────────────────────────────────────────────────────────────────────────────
# GCS buckets
# ──────────────────────────────────────────────────────────────────────────────

# spotify-raw: holds daily CSV snapshots from the Cloud Function (Phase 2/3).
resource "google_storage_bucket" "spotify_raw" {
  name                        = "${var.project_id}-spotify-raw"
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = {
    managed_by = "terraform"
    purpose    = "raw-snapshots"
  }
}

# ci-state: holds the prod dbt manifest for Slim CI deferral (Phase 8).
resource "google_storage_bucket" "ci_state" {
  name                        = "${var.project_id}-ci-state"
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true

  labels = {
    managed_by = "terraform"
    purpose    = "ci-state"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# BigQuery datasets
# ──────────────────────────────────────────────────────────────────────────────

locals {
  datasets = {
    spotify_raw               = "Raw daily snapshots from snapshot.py (Phase 2)"
    spotify_analytics_dev     = "Local laptop dbt target (Phase 7)"
    spotify_analytics_ci      = "Per-PR validation dataset (Phase 6/8 fallback)"
    spotify_analytics_staging = "Auto-deploy on merge to main (Phase 7)"
    spotify_analytics_prod    = "Manual promote via Actions UI (Phase 7/9)"
  }
}

resource "google_bigquery_dataset" "analytics" {
  for_each   = local.datasets
  dataset_id = each.key
  project    = var.project_id
  location   = var.location

  description = each.value
  labels = {
    managed_by = "terraform"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Service accounts
# ──────────────────────────────────────────────────────────────────────────────

resource "google_service_account" "ingest_fn" {
  account_id   = "spotify-ingest-fn"
  display_name = "Spotify ingest function runtime"
  project      = var.project_id
}

resource "google_service_account" "scheduler" {
  account_id   = "spotify-scheduler"
  display_name = "Cloud Scheduler -> Cloud Function invoker"
  project      = var.project_id
}

resource "google_service_account" "dbt_ci" {
  account_id   = "dbt-ci"
  display_name = "dbt CI runner (Phase 6 — Level 1)"
  project      = var.project_id
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM
# ──────────────────────────────────────────────────────────────────────────────

# Function runtime: bucket write + BQ load/insert.
resource "google_storage_bucket_iam_member" "ingest_fn_bucket" {
  bucket = google_storage_bucket.spotify_raw.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ingest_fn.email}"
}

resource "google_project_iam_member" "ingest_fn_bq_job" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.ingest_fn.email}"
}

resource "google_project_iam_member" "ingest_fn_bq_data" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.ingest_fn.email}"
}

# dbt-ci: project-wide BQ job + dataEditor (Phase 6's Level-1 tradeoff;
# Phase 11 narrows to per-env-project SAs).
resource "google_project_iam_member" "dbt_ci_bq_job" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt_ci.email}"
}

resource "google_project_iam_member" "dbt_ci_bq_data" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dbt_ci.email}"
}

# dbt-ci on the ci-state bucket: read prod manifest + write prod manifest.
resource "google_storage_bucket_iam_member" "dbt_ci_ci_state" {
  bucket = google_storage_bucket.ci_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dbt_ci.email}"
}

# scheduler SA's run.invoker on the Cloud Function is set by deploy.sh because
# the Cloud Run service is created by `gcloud functions deploy`, not Terraform.

# ──────────────────────────────────────────────────────────────────────────────
# Billing budget (~$5)
# ──────────────────────────────────────────────────────────────────────────────

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_billing_budget" "five_dollars" {
  billing_account = var.billing_account_id
  display_name    = "${var.project_id} (~$5)"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = var.budget_amount_units
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }
}
