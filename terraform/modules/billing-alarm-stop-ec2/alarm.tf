data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  tags = [for k, v in var.tags : { key = k, value = v }]

  # Currency is always present. ServiceName is added only when scoping to a
  # single service, because an alarm carrying ServiceName = null would match no
  # published metric at all.
  dimensions = concat(
    [{ name = "Currency", value = "USD" }],
    var.service_name == null ? [] : [{ name = "ServiceName", value = var.service_name }],
  )

  scope_description = var.service_name == null ? "total account charges" : "${var.service_name} charges"
}

# AWS publishes AWS/Billing only in us-east-1. Applied anywhere else, CloudWatch
# still creates the alarm — it simply never receives a datapoint and sits in
# INSUFFICIENT_DATA forever. That is a billing alarm that silently never fires,
# so this fails the plan rather than leaving a comment.
resource "terraform_data" "region_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_region.current.region == "us-east-1"
      error_message = "This module must be applied in us-east-1. AWS publishes the AWS/Billing namespace only there, so an alarm created in ${data.aws_region.current.region} would never receive data and never fire."
    }
  }
}

resource "awscc_cloudwatch_alarm" "this" {
  alarm_name        = "${var.name}-estimated-charges"
  alarm_description = "Estimated ${local.scope_description} exceeded ${var.threshold_usd} USD. Stops EC2 instances tagged ${var.stoppable_tag_key}=${var.stoppable_tag_value}."
  actions_enabled   = true

  namespace   = "AWS/Billing"
  metric_name = "EstimatedCharges"

  # EstimatedCharges is a running month-to-date total, so Maximum is the only
  # statistic reflecting the current bill. Average or Sum would understate or
  # double-count it.
  statistic = "Maximum"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.threshold_usd
  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods

  # Billing data is delayed and pauses at month roll-over. "missing" retains the
  # current state on an absent datapoint, which is what AWS recommends and the
  # safer of the non-breaching options: "notBreaching" would clear a live ALARM
  # simply because data stopped arriving. Never "breaching" — that would stop
  # instances on absent data rather than real spend.
  treat_missing_data = "missing"

  # No alarm_actions on purpose. CloudWatch publishes every state change to the
  # default EventBridge bus with no configuration on the alarm, and events.tf
  # matches it there. Setting alarm_actions would add a second, parallel path.

  dimensions = local.dimensions

  tags = local.tags

  depends_on = [terraform_data.region_guard]
}
