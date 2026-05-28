# Workload Identity Federation: GitHub OIDC → impersonates per-env dbt-ci SAs.
# No SA key JSON anywhere.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Federates GitHub OIDC tokens to GCP SAs"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # SECURITY BOUNDARY: only THIS repo's OIDC tokens may exchange for GCP creds.
  # repository_id is the immutable numeric id; survives repo renames.
  attribute_condition = "assertion.repository_id == \"${var.github_repository_id}\""

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.repository_id"    = "assertion.repository_id"
    "attribute.ref"              = "assertion.ref"
    "attribute.environment"      = "assertion.environment"
    "attribute.event_name"       = "assertion.event_name"
  }
}

# Bind each per-env dbt-ci SA to be impersonatable by the GitHub repo via WIF.
resource "google_service_account_iam_member" "wif_impersonation" {
  for_each = {
    for s in var.impersonatable_sas : "${s.project_id}-${s.sa_email}" => s
  }
  service_account_id = "projects/${each.value.project_id}/serviceAccounts/${each.value.sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
