# Deploying Lizard

Lizard watches EC2 estimated charges and **stops every running EC2 instance
tagged `StoppableBy=Lizard`** when spend crosses your threshold.

## What it does not do

Read this first — it is the difference between real protection and false
confidence.

A billing alarm reports that a *service* went over. It carries no instance
identity, so **Lizard cannot find the instance responsible for the spend.** You
decide in advance which instances are expendable, by tagging them.

- An untagged instance burning money **will not be stopped**.
- Every tagged instance is stopped, not just the expensive one.
- Instances are stopped, never terminated — EBS volumes and instance IDs survive,
  and you can start them again.
- **Instance store data does not survive a stop.** Ephemeral NVMe disks are tied
  to the host; a stopped instance restarts on a different one with empty local
  disks. This affects `d`-suffix and storage-optimised families (`m5d`, `i3`,
  `i4i`, …). If a tagged instance keeps anything it cares about on local storage,
  treat a Lizard trigger as data loss.

It is a circuit breaker with a blast radius you declare, not a targeted fix.

## Before you start

**1. Enable billing alerts** in the payer account: Billing and Cost Management →
Billing Preferences → *Receive CloudWatch Billing Alerts*. Without this AWS
publishes no data and the alarm sits in `INSUFFICIENT_DATA` forever. Allow ~15
minutes, then confirm:

```bash
aws cloudwatch list-metrics --namespace AWS/Billing \
  --metric-name EstimatedCharges --region us-east-1
```

Empty output means it has not taken effect. Wait.

**2. Use us-east-1.** AWS publishes billing metrics only there. Applied
elsewhere, Terraform fails the plan rather than building an alarm that can never
fire.

**3. Grant the permissions below.**

## Permissions

The deploying identity needs this. `cloudcontrol:*` is easy to miss — the
`awscc` provider calls the Cloud Control API, so both it *and* the underlying
service actions are required.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudControlAndServices",
      "Effect": "Allow",
      "Action": [
        "cloudcontrol:CancelResourceRequest",
        "cloudcontrol:CreateResource",
        "cloudcontrol:DeleteResource",
        "cloudcontrol:GetResource",
        "cloudcontrol:ListResources",
        "cloudcontrol:UpdateResource",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListTagsForResource",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:TagResource",
        "cloudwatch:UntagResource",
        "events:DeleteRule",
        "events:DescribeRule",
        "events:ListTagsForResource",
        "events:ListTargetsByRule",
        "events:PutRule",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:TagResource",
        "events:UntagResource",
        "ssm:AddTagsToResource",
        "ssm:CreateDocument",
        "ssm:DeleteDocument",
        "ssm:DescribeDocument",
        "ssm:GetDocument",
        "ssm:ListTagsForResource",
        "ssm:RemoveTagsFromResource",
        "ssm:UpdateDocument",
        "ssm:UpdateDocumentDefaultVersion",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Sid": "StateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteObject",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:GetBucketPolicy",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketTagging",
        "s3:GetBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutBucketPolicy",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketTagging",
        "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration",
        "s3:PutLifecycleConfiguration",
        "s3:PutObject"
      ],
      "Resource": ["arn:aws:s3:::lizard-tfstate-*", "arn:aws:s3:::lizard-tfstate-*/*"]
    },
    {
      "Sid": "TheTwoRolesLizardCreates",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:DeleteRolePolicy",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListRoleTags",
        "iam:PutRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:UpdateAssumeRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/*-stop-ec2-*"
    },
    {
      "Sid": "PassInvocationRoleToEventBridge",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/*-stop-ec2-*",
      "Condition": {
        "StringEquals": { "iam:PassedToService": "events.amazonaws.com" }
      }
    }
  ]
}
```

**Keep the IAM `Resource` scoped.** `iam:PutRolePolicy` on `*` would let anyone
holding this policy grant themselves anything.

Check what you actually have rather than assuming — an SSO permission set named
`PowerUserAccess` may carry more than that policy:

```bash
ARN=$(aws sts get-caller-identity --query Arn --output text)
aws iam simulate-principal-policy \
  --policy-source-arn "$(echo "$ARN" | sed 's#:sts:#:iam:#; s#assumed-role/#role/#; s#/[^/]*$##')" \
  --action-names iam:CreateRole iam:PutRolePolicy iam:PassRole \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text
```

## Deploy

**1. Create the state bucket** (once per account):

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
terraform -chdir=terraform/bootstrap output backend_hcl
```

**2. Tag the instances you are willing to lose** — before deploying, so the
alarm has something to act on when it fires:

```bash
aws ec2 create-tags --resources i-0123456789abcdef0 \
  --tags Key=StoppableBy,Value=Lizard --region us-east-1
```

**3. Deploy the alarm and remediation:**

```bash
cd terraform/examples/stop-tagged-ec2
cp backend.hcl.example backend.hcl        # fill in from step 1's output
terraform init -backend-config=backend.hcl
terraform apply -var 'threshold_usd=50'
```

If month-to-date EC2 spend already exceeds your threshold, the alarm fires
immediately and instances stop within a minute or two. Choose the number
deliberately.

## Verify it works

Do not wait for a real bill. Force the alarm — this emits a genuine state-change
event, so everything downstream runs exactly as in production.

Use a throwaway instance. It really does stop it.

```bash
A=$(terraform output -raw alarm_name)

# EventBridge fires on the transition into ALARM, so reset to OK first
aws cloudwatch set-alarm-state --alarm-name "$A" --state-value OK \
  --state-reason reset --region us-east-1
aws cloudwatch set-alarm-state --alarm-name "$A" --state-value ALARM \
  --state-reason "Testing Lizard" --region us-east-1
```

Then check, in order:

```bash
# 1. The automation ran and succeeded
aws ssm describe-automation-executions --region us-east-1 \
  --filters Key=DocumentNamePrefix,Values="$(terraform output -raw document_name)"

# 2. Tagged instances stopped; untagged ones did not
aws ec2 describe-instances --region us-east-1 \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`StoppableBy`].Value|[0]]' \
  --output table
```

An untagged instance that stopped would mean the tag boundary is broken. It is
enforced in IAM, not just in the runbook, so this should not happen.

If nothing ran, check `FailedInvocations` on the rule and look for
`AccessDenied` in CloudTrail.

The alarm returns to its real state at the next evaluation.

## Tuning

| Variable | Default | Notes |
| --- | --- | --- |
| `threshold_usd` | — | required |
| `service_name` | `AmazonEC2` in the example | `null` watches total account spend |
| `stoppable_tag_key` / `_value` | `StoppableBy` / `Lizard` | changing these moves the blast radius |
| `period_seconds` | `21600` | AWS publishes billing data ~every 6h; shorter is pointless |
| `evaluation_periods` | `1` | |
