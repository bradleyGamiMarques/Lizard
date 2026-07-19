output "alarm_name" {
  description = "Name of the billing alarm to watch in the CloudWatch console."
  value       = module.billing_alarm_stop_ec2.alarm_name
}

output "document_name" {
  description = "SSM Automation runbook that stops the tagged instances."
  value       = module.billing_alarm_stop_ec2.document_name
}

output "stoppable_tag" {
  description = "Tag an instance must carry to be stoppable."
  value       = module.billing_alarm_stop_ec2.stoppable_tag
}
