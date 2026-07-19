output "state_bucket" {
  description = "Name of the state bucket."
  value       = aws_s3_bucket.state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.state.arn
}

output "backend_hcl" {
  description = <<-EOT
    Ready-to-paste contents for terraform/billing-alarm/backend.hcl, which is
    gitignored because the bucket name is account-specific.
  EOT
  value       = <<-EOT
    bucket = "${aws_s3_bucket.state.bucket}"
    region = "${var.aws_region}"
  EOT
}
