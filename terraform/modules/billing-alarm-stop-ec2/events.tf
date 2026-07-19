locals {
  # An EventBridge target for SSM Automation is the automation-definition ARN,
  # not the document name, and the version suffix is required.
  automation_definition_arn_base = join("", [
    "arn:", data.aws_partition.current.partition,
    ":ssm:", data.aws_region.current.region,
    ":", data.aws_caller_identity.current.account_id,
    ":automation-definition/", local.document_name,
  ])

  automation_definition_arn = "${local.automation_definition_arn_base}:$DEFAULT"

  # Narrowed to this one alarm and the ALARM state, so no unrelated alarm in the
  # account can stop instances, and recovery to OK does not re-trigger.
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [awscc_cloudwatch_alarm.this.alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })

  # SSM takes every Automation parameter as a list of strings.
  target_input = jsonencode({
    AutomationAssumeRole = [awscc_iam_role.automation.arn]
  })
}

resource "awscc_events_rule" "this" {
  name        = "${var.name}-stop-ec2-on-billing-alarm"
  description = "Stops EC2 instances tagged ${var.stoppable_tag_key}=${var.stoppable_tag_value} when ${awscc_cloudwatch_alarm.this.alarm_name} enters ALARM."
  state       = "ENABLED"

  event_pattern = local.event_pattern

  targets = [{
    # Rule names are capped at 64 characters, and the target id shares that
    # limit; deriving it from a truncated name keeps both inside the bound.
    id       = substr("${var.name}-stop-ec2", 0, 64)
    arn      = local.automation_definition_arn
    role_arn = awscc_iam_role.invocation.arn
    input    = local.target_input
  }]
}
