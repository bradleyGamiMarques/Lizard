# Stop tagged EC2 instances when EC2 spend crosses a threshold.
#
# The alarm watches EstimatedCharges scoped to ServiceName = AmazonEC2, so it
# reacts to EC2 spend rather than the account total. When it enters ALARM,
# EventBridge starts an SSM Automation that stops every running instance tagged
# StoppableBy=Lizard.
#
# This example creates no EC2 instances. Tag instances you already own, and be
# deliberate about it — the tag is the entire blast radius.

module "billing_alarm_stop_ec2" {
  source = "../../modules/billing-alarm-stop-ec2"

  name          = var.name
  threshold_usd = var.threshold_usd

  # Omit this to alarm on the account's total estimated charges instead.
  service_name = "AmazonEC2"

  tags = {
    Project   = "Lizard"
    ManagedBy = "Terraform"
  }
}
