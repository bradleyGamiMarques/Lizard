variable "aws_region" {
  description = "Region that holds the Terraform state bucket."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = <<-EOT
    Name of the S3 bucket holding Terraform state. S3 bucket names are globally
    unique across all AWS accounts, so leave this null to derive a name from the
    account ID.
  EOT
  type        = string
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain superseded state versions before expiring them."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "Retention must be at least 1 day."
  }
}
