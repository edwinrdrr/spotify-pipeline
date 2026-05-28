output "provider_name" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "Full path of the WIF provider — what workflows pass to google-github-actions/auth"
}

output "pool_name" {
  value = google_iam_workload_identity_pool.github.name
}
