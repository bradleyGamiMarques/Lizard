# Stop tagged EC2 instances on a billing alarm

Watches EC2 estimated charges. When they cross the threshold, every **running**
EC2 instance tagged `StoppableBy=Lizard` is stopped.

Full instructions — prerequisites, IAM policy, verification — are in
[docs/deploying.md](../../../docs/deploying.md).

```bash
cp backend.hcl.example backend.hcl     # from `terraform -chdir=../../bootstrap output backend_hcl`
terraform init -backend-config=backend.hcl
terraform apply -var 'threshold_usd=50'
```

## Things worth knowing

**Tag instances before applying.** If month-to-date spend already exceeds the
threshold, the alarm fires as soon as it is created.

**Only tagged instances stop, and all of them do.** Lizard cannot identify which
instance caused the spend. The tag is the blast radius, enforced by an IAM
condition on `ec2:StopInstances` rather than only by the runbook.

**If nothing carries the tag, the automation fails.** `StopInstances` rejects an
empty list. That is deliberate: the alarm fired and Lizard had nothing it was
permitted to stop, which is worth surfacing rather than reporting as success.

**us-east-1 only.** AWS publishes billing metrics nowhere else, and the module
fails the plan rather than creating an alarm that can never fire.

## Variables

Set `service_name = null` to watch total account spend instead of EC2 alone.
Other defaults are in [`../../modules/billing-alarm-stop-ec2/variables.tf`](../../modules/billing-alarm-stop-ec2/variables.tf).
