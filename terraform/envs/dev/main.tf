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
  env             = "dev"
  region          = var.region
  location        = var.location
  deploy_function = false # dev runs ingestion locally only
}

output "project_id" {
  value = module.data.project_id
}

output "dbt_ci_sa_email" {
  value = module.data.dbt_ci_sa_email
}

output "raw_bucket" {
  value = module.data.raw_bucket
}
