variable "name" {
  description = "Short name for this deployment. Prefixes the alarm, document, rule, and both IAM roles."
  type        = string
  default     = "lizard"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 lower-case alphanumeric or hyphen characters, and may not start or end with a hyphen."
  }
}

variable "threshold_usd" {
  description = "Estimated charges, in USD, above which the alarm enters ALARM and instances are stopped."
  type        = number

  validation {
    condition     = var.threshold_usd > 0
    error_message = "threshold_usd must be greater than 0."
  }
}

variable "service_name" {
  description = <<-EOT
    Value for the ServiceName dimension of EstimatedCharges, scoping the alarm to
    one service — "AmazonEC2" for EC2 spend. Leave null to alarm on the account's
    total estimated charges instead.

    These are AWS's internal service names, not display names: AmazonEC2 rather
    than "EC2", AWSLambda rather than "Lambda". A value AWS does not publish
    produces an alarm that receives no data and therefore never fires.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.service_name == null || can(regex("^[A-Za-z0-9]+$", coalesce(var.service_name, "x")))
    error_message = "service_name must be an AWS internal service name such as AmazonEC2 (alphanumeric, no spaces or punctuation)."
  }
}

variable "stoppable_tag_key" {
  description = <<-EOT
    Tag key marking an instance as safe to stop. This is a permission boundary,
    not just a filter: the automation role's ec2:StopInstances grant is
    conditioned on this tag, so an instance without it cannot be stopped even if
    the runbook tries.
  EOT
  type        = string
  default     = "StoppableBy"

  validation {
    condition     = length(var.stoppable_tag_key) > 0
    error_message = "stoppable_tag_key must not be empty."
  }
}

variable "stoppable_tag_value" {
  description = "Tag value paired with stoppable_tag_key. See that variable for why this is load-bearing."
  type        = string
  default     = "Lizard"

  validation {
    condition     = length(var.stoppable_tag_value) > 0
    error_message = "stoppable_tag_value must not be empty."
  }
}

variable "period_seconds" {
  description = <<-EOT
    Evaluation period in seconds. AWS refreshes EstimatedCharges roughly every
    six hours, so anything shorter only produces evaluation windows containing no
    datapoint.
  EOT
  type        = number
  default     = 21600

  validation {
    condition     = var.period_seconds >= 21600
    error_message = "period_seconds must be at least 21600 (6 hours), the publish interval of EstimatedCharges."
  }
}

variable "evaluation_periods" {
  description = "Number of consecutive periods over threshold before the alarm fires."
  type        = number
  default     = 1

  validation {
    condition     = var.evaluation_periods >= 1 && floor(var.evaluation_periods) == var.evaluation_periods
    error_message = "evaluation_periods must be a whole number of at least 1."
  }
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
