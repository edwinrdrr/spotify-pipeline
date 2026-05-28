variable "project_id" {
  type        = string
  description = "GCP project id for this env"
}

variable "env" {
  type        = string
  description = "Environment name (dev / staging / prod) — used in labels"
}

variable "region" {
  type        = string
  default     = "us-central1"
}

variable "location" {
  type        = string
  default     = "US"
}

variable "deploy_function" {
  type        = bool
  description = "Create the function-runtime + scheduler SAs (staging/prod only)"
  default     = false
}
