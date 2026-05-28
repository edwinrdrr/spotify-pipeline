# Infra project — cross-cutting:
#   - tfstate bucket (imported on first apply; the bucket creates itself out-of-band)
#   - ci-state bucket (Slim CI manifest)
#   - WIF pool + provider (bound to spotify-pipeline repo only)
#   - Per-env dbt-ci SA impersonation bindings

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
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "location" {
  type    = string
  default = "US"
}

variable "dev_project_id" {
  type = string
}

variable "staging_project_id" {
  type = string
}

variable "prod_project_id" {
  type = string
}

variable "github_repository" {
  type = string
}

variable "github_repository_id" {
  type = string
}

# Cross-cutting APIs in the infra project.
resource "google_project_service" "apis" {
  for_each = toset([
    "storage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "sts.googleapis.com",
    "billingbudgets.googleapis.com",
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# tfstate bucket (this very bucket holds THIS state file via backend.tf).
# Bootstrap script creates it out-of-band, then this resource imports it.
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  labels = {
    env        = "infra"
    managed_by = "terraform"
    purpose    = "tfstate"
  }
}

# Slim CI manifest bucket — read by PR CI, written by prod workflow.
resource "google_storage_bucket" "ci_state" {
  name                        = "${var.project_id}-ci-state"
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true

  labels = {
    env        = "infra"
    managed_by = "terraform"
    purpose    = "ci-state"
  }
}

# Grant each env's dbt-ci SA access to read+write the ci-state bucket (for Slim CI).
locals {
  env_sas_for_ci_state = [
    "dbt-ci@${var.dev_project_id}.iam.gserviceaccount.com",
    "dbt-ci@${var.staging_project_id}.iam.gserviceaccount.com",
    "dbt-ci@${var.prod_project_id}.iam.gserviceaccount.com",
  ]
}

resource "google_storage_bucket_iam_member" "ci_state_writers" {
  for_each = toset(local.env_sas_for_ci_state)
  bucket   = google_storage_bucket.ci_state.name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${each.key}"
}

# WIF — repo-scoped impersonation of per-env dbt-ci SAs.
module "wif" {
  source               = "../../modules/wif"
  project_id           = var.project_id
  github_repository    = var.github_repository
  github_repository_id = var.github_repository_id

  impersonatable_sas = [
    { sa_email = "dbt-ci@${var.dev_project_id}.iam.gserviceaccount.com",     project_id = var.dev_project_id },
    { sa_email = "dbt-ci@${var.staging_project_id}.iam.gserviceaccount.com", project_id = var.staging_project_id },
    { sa_email = "dbt-ci@${var.prod_project_id}.iam.gserviceaccount.com",    project_id = var.prod_project_id },
  ]
}

output "tfstate_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "ci_state_bucket" {
  value = google_storage_bucket.ci_state.name
}

output "wif_provider_name" {
  value = module.wif.provider_name
}
