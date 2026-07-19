variable "name" {
  description = "Short name prefixing every resource this example creates."
  type        = string
  default     = "lizard"
}

variable "threshold_usd" {
  description = <<-EOT
    EC2 estimated charges, in USD, above which tagged instances are stopped.

    Set this deliberately. If your current month-to-date EC2 spend already
    exceeds it, the alarm enters ALARM as soon as it is created and instances
    are stopped within minutes.
  EOT
  type        = number
  default     = 50
}
