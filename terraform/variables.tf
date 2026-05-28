variable "project_id" {
  type        = string
  description = "GCP project id (e.g. spotify-pipeline-260528)"
}

variable "region" {
  type        = string
  description = "Default region for region-scoped resources (Cloud Run, Scheduler etc.)"
  default     = "us-central1"
}

variable "location" {
  type        = string
  description = "Multi-region for GCS + BigQuery"
  default     = "US"
}

variable "billing_account_id" {
  type        = string
  description = "Billing account id (e.g. 012D5A-0DD848-C2502B)"
}

variable "budget_currency" {
  type        = string
  description = "Currency code matching your billing account (IDR/USD/EUR/...)"
  default     = "IDR"
}

variable "budget_amount_units" {
  type        = string
  description = "Whole-currency amount approx 5 USD (IDR ~80000, USD 5, EUR 4, ...)"
  default     = "80000"
}
