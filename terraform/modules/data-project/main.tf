# Per-env data project: bucket + 2 datasets + per-env dbt-ci SA + optional function SAs.
# Resource names DROP the env suffix — the project IS the env.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

locals {
  apis_base = [
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
  ]
  apis_function = [
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
    "cloudscheduler.googleapis.com",
  ]
  apis = concat(local.apis_base, var.deploy_function ? local.apis_function : [])

  common_labels = {
    env        = var.env
    managed_by = "terraform"
    repo       = "spotify-pipeline"
  }
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# ─── Storage ──────────────────────────────────────────────────────────────────

resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-spotify-raw"
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = local.common_labels
}

# ─── BigQuery ─────────────────────────────────────────────────────────────────

# Drop env suffix from dataset names: project IS the env, so the dataset is just
# "spotify_raw" / "spotify_analytics" everywhere.
resource "google_bigquery_dataset" "raw" {
  dataset_id  = "spotify_raw"
  project     = var.project_id
  location    = var.location
  description = "Raw daily snapshots (env=${var.env})"
  labels      = local.common_labels
}

resource "google_bigquery_dataset" "analytics" {
  dataset_id  = "spotify_analytics"
  project     = var.project_id
  location    = var.location
  description = "dbt staging + marts (env=${var.env})"
  labels      = local.common_labels
}

# ─── Service accounts ────────────────────────────────────────────────────────

# dbt-ci@<env-project>: built (and impersonated via WIF) by the dbt workflows.
resource "google_service_account" "dbt_ci" {
  account_id   = "dbt-ci"
  display_name = "dbt CI runner (env=${var.env})"
  project      = var.project_id
}

# function runtime + scheduler SAs only in envs that deploy the function.
resource "google_service_account" "ingest_fn" {
  count        = var.deploy_function ? 1 : 0
  account_id   = "spotify-ingest-fn"
  display_name = "Spotify ingest function runtime (env=${var.env})"
  project      = var.project_id
}

resource "google_service_account" "scheduler" {
  count        = var.deploy_function ? 1 : 0
  account_id   = "spotify-scheduler"
  display_name = "Cloud Scheduler -> function invoker (env=${var.env})"
  project      = var.project_id
}

# ─── IAM ─────────────────────────────────────────────────────────────────────

# dbt-ci: BQ jobUser + dataEditor (per-env-project — narrower than Phase 6's project-wide)
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

# function runtime: storage write + BQ load
resource "google_storage_bucket_iam_member" "ingest_fn_bucket" {
  count  = var.deploy_function ? 1 : 0
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ingest_fn[0].email}"
}

resource "google_project_iam_member" "ingest_fn_bq_job" {
  count   = var.deploy_function ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.ingest_fn[0].email}"
}

resource "google_project_iam_member" "ingest_fn_bq_data" {
  count   = var.deploy_function ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.ingest_fn[0].email}"
}
