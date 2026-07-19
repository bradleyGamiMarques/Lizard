output "alarm_name" {
  description = "Name of the billing alarm."
  value       = awscc_cloudwatch_alarm.this.alarm_name
}

output "alarm_arn" {
  description = "ARN of the billing alarm."
  value       = awscc_cloudwatch_alarm.this.arn
}

output "document_name" {
  description = "Name of the SSM Automation runbook that stops the tagged instances."
  value       = awscc_ssm_document.stop_tagged_ec2.name
}

output "automation_definition_arn" {
  description = "Automation definition ARN targeted by the rule, including version suffix."
  value       = local.automation_definition_arn
}

output "rule_name" {
  description = "Name of the EventBridge rule."
  value       = awscc_events_rule.this.name
}

output "automation_role_arn" {
  description = "ARN of the role SSM assumes. Carries the tag-conditioned ec2:StopInstances grant."
  value       = awscc_iam_role.automation.arn
}

output "invocation_role_arn" {
  description = "ARN of the role EventBridge assumes to start the automation."
  value       = awscc_iam_role.invocation.arn
}

output "stoppable_tag" {
  description = "Tag an instance must carry to be stoppable, as key=value."
  value       = "${var.stoppable_tag_key}=${var.stoppable_tag_value}"
}
