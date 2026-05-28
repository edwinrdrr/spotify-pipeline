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

# ─── Phase 12: tf-runner SA for terraform plan/apply CI ──────────────────────

resource "google_service_account" "tf_runner" {
  account_id   = "tf-runner"
  display_name = "Terraform CI runner (plan-on-PR + apply-on-merge)"
  project      = var.project_id
}

# tf-runner needs editor on each project to manage the same resources Terraform
# already manages (buckets, datasets, SAs, IAM, APIs). Editor is broad but standard
# for a TF runner SA; the review/approval gate is at the GitHub Actions / Environment
# level (terraform-apply requires reviewer approval).
locals {
  tf_runner_projects = [
    var.project_id,
    var.dev_project_id,
    var.staging_project_id,
    var.prod_project_id,
  ]
}

resource "google_project_iam_member" "tf_runner_editor" {
  for_each = toset(local.tf_runner_projects)
  project  = each.key
  role     = "roles/editor"
  member   = "serviceAccount:${google_service_account.tf_runner.email}"
}

# Need projectIamAdmin too — `roles/editor` doesn't include setIamPolicy on the
# project, which Terraform needs for google_project_iam_member resources.
resource "google_project_iam_member" "tf_runner_iam_admin" {
  for_each = toset(local.tf_runner_projects)
  project  = each.key
  role     = "roles/resourcemanager.projectIamAdmin"
  member   = "serviceAccount:${google_service_account.tf_runner.email}"
}

# Read+write access to tfstate bucket (plan needs read; apply needs write).
resource "google_storage_bucket_iam_member" "tf_runner_tfstate" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.tf_runner.email}"
}

# WIF — repo-scoped impersonation of per-env dbt-ci SAs + tf-runner.
module "wif" {
  source               = "../../modules/wif"
  project_id           = var.project_id
  github_repository    = var.github_repository
  github_repository_id = var.github_repository_id

  impersonatable_sas = [
    { sa_email = "dbt-ci@${var.dev_project_id}.iam.gserviceaccount.com",     project_id = var.dev_project_id },
    { sa_email = "dbt-ci@${var.staging_project_id}.iam.gserviceaccount.com", project_id = var.staging_project_id },
    { sa_email = "dbt-ci@${var.prod_project_id}.iam.gserviceaccount.com",    project_id = var.prod_project_id },
    { sa_email = "tf-runner@${var.project_id}.iam.gserviceaccount.com",        project_id = var.project_id },
  ]

  # tf-runner SA must exist before WIF impersonation binding references it.
  depends_on = [google_service_account.tf_runner]
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

output "tf_runner_sa_email" {
  value = google_service_account.tf_runner.email
}
