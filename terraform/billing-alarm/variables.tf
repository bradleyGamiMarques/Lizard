variable "aws_region" {
  description = <<-EOT
    Region the billing-alarm resources are created in. AWS publishes the
    AWS/Billing CloudWatch namespace only in us-east-1, so the alarm that watches
    EstimatedCharges must live there regardless of where the resources it acts on
    are.
  EOT
  type        = string
  default     = "us-east-1"
}
