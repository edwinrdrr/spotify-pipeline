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

module "data" {
  source          = "../../modules/data-project"
  project_id      = var.project_id
  env             = "prod"
  region          = var.region
  location        = var.location
  deploy_function = true # function + scheduler at daily cadence (deploy.sh)
}

output "project_id" {
  value = module.data.project_id
}

output "dbt_ci_sa_email" {
  value = module.data.dbt_ci_sa_email
}

output "ingest_fn_sa_email" {
  value = module.data.ingest_fn_sa_email
}

output "scheduler_sa_email" {
  value = module.data.scheduler_sa_email
}

output "raw_bucket" {
  value = module.data.raw_bucket
}
