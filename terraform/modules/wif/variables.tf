variable "project_id" {
  type        = string
  description = "Infra project — WIF pool + provider live here"
}

variable "pool_id" {
  type    = string
  default = "github-actions"
}

variable "provider_id" {
  type    = string
  default = "github"
}

variable "github_repository" {
  type        = string
  description = "owner/repo (e.g. edwinrdrr/spotify-pipeline)"
}

variable "github_repository_id" {
  type        = string
  description = "Numeric GitHub repository_id — pin the WIF attribute condition to THIS repo only"
}

variable "impersonatable_sas" {
  type = list(object({
    sa_email   = string
    project_id = string
  }))
  description = "Per-env dbt-ci SAs to bind for impersonation by the GitHub repo"
}
