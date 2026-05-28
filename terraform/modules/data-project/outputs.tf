output "project_id" {
  value = var.project_id
}

output "dbt_ci_sa_email" {
  value = google_service_account.dbt_ci.email
}

output "ingest_fn_sa_email" {
  value       = var.deploy_function ? google_service_account.ingest_fn[0].email : null
  description = "null in dev (no function deployed)"
}

output "scheduler_sa_email" {
  value       = var.deploy_function ? google_service_account.scheduler[0].email : null
  description = "null in dev (no function deployed)"
}

output "raw_bucket" {
  value = google_storage_bucket.raw.name
}
