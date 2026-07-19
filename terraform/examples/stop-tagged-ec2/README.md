# Stop tagged EC2 instances on a billing alarm

Watches EC2 estimated charges. When they cross the threshold, every **running**
EC2 instance tagged `StoppableBy=Lizard` is stopped.

## What this does and does not do

**It is a kill switch with a blast radius you declare in advance.**

A billing alarm reports that a *service* went over. It carries no instance
identity, so nothing here can find the instance responsible for the spend. You
decide beforehand which instances are expendable, by tagging them, and the alarm
pulls that lever.

Consequences worth understanding before you apply this:

- An instance that is burning money but is **not** tagged will not be stopped.
  Spend keeps climbing while the alarm sits in ALARM, already fired.
- Every tagged instance is stopped, not just the expensive one.
- Instances are **stopped, never terminated**. EBS-backed volumes persist; data
  on instance store volumes does not survive a stop.

## Prerequisites

1. **Billing alerts must be enabled** in the payer account, under Billing and
   Cost Management → Billing Preferences → *Receive CloudWatch Billing Alerts*.
   Without this AWS publishes no `EstimatedCharges` data at all and the alarm
   sits in `INSUFFICIENT_DATA` forever. It takes about 15 minutes to start
   flowing after you enable it.
2. **us-east-1.** AWS publishes `AWS/Billing` only there. The module fails the
   plan elsewhere rather than creating an alarm that can never fire.
3. **Deploy permissions.** See [docs/permissions.md](../../../docs/permissions.md).
   Note that `awscc` resources need `cloudcontrol:*` actions *in addition to* the
   underlying service permissions — granting only `cloudwatch:PutMetricAlarm` is
   not enough.

## Usage

```bash
terraform init
terraform plan -var 'threshold_usd=50'
terraform apply -var 'threshold_usd=50'
```

Then tag the instances you are willing to lose:

```bash
aws ec2 create-tags \
  --resources i-0123456789abcdef0 \
  --tags Key=StoppableBy,Value=Lizard
```

## Verifying it works

Do not wait for a real bill. Force the alarm state:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name "$(terraform output -raw alarm_name)" \
  --state-value ALARM \
  --state-reason "Testing Lizard remediation"
```

That emits a genuine state-change event, so EventBridge and the automation run
exactly as they would in production. Watch the result under Systems Manager →
Automation. The alarm returns to its real state at the next evaluation.

Use a disposable instance for this. It really does stop it.

## If no instance carries the tag

The automation **fails**, with `StopInstances` rejecting an empty instance list.

That is deliberate. It means the alarm fired while Lizard had nothing it was
permitted to stop, which is worth surfacing rather than reporting as a
successful remediation.

## Why the tag is enforced twice

The runbook filters on the tag, and the automation role's `ec2:StopInstances`
grant is *conditioned* on the same tag:

```json
"Condition": { "StringEquals": { "ec2:ResourceTag/StoppableBy": "Lizard" } }
```

The IAM condition is the real boundary. Even a buggy or replaced runbook cannot
stop an untagged instance, because the role has no permission to.
