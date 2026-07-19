# Permissions needed to deploy Lizard

Three separate things need permissions, and they are easy to conflate:

1. **You**, or your CI role, deploying the Terraform.
2. **The state backend**, reading and writing the state object and its lock.
3. **The roles Lizard creates**, which act at runtime when the alarm fires.
   Those are defined by the module itself and documented in
   [the example README](../terraform/examples/stop-tagged-ec2/README.md) — you do
   not grant them, Terraform does.

This page covers 1 and 2.

## Prerequisite: billing alerts

Before any of this, **billing alerts must be enabled in the payer account**,
under Billing and Cost Management → Billing Preferences → *Receive CloudWatch
Billing Alerts*. Without it AWS publishes no `EstimatedCharges` data at all, and
every alarm Lizard creates sits in `INSUFFICIENT_DATA` forever.

This is a console action requiring billing-preferences permission on the payer
account, not something Terraform does. It takes roughly 15 minutes before data
starts flowing.

## The `awscc` gotcha

The alarm, runbook, rule, and IAM roles are created through the `awscc`
provider, which calls the **AWS Cloud Control API** rather than each service's
own API. That means the deploying principal needs **both**:

- `cloudcontrol:*` actions — the Cloud Control API itself, and
- the underlying service permissions, because Cloud Control performs the real
  operation using *your* credentials.

A policy granting only `cloudwatch:PutMetricAlarm` fails, and so does one
granting only `cloudcontrol:CreateResource`. Both are required. This surprises
people who have used the classic `aws` provider, where the service action alone
is enough.

## 1. Bootstrap stack

Creates the S3 bucket holding Terraform state. Run once per account. Uses the
classic `aws` provider, so no `cloudcontrol` actions are involved.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateAndConfigureStateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:GetBucketPolicy",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketTagging",
        "s3:GetBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:PutBucketPolicy",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketTagging",
        "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration",
        "s3:PutLifecycleConfiguration"
      ],
      "Resource": "arn:aws:s3:::lizard-tfstate-*"
    },
    {
      "Sid": "IdentifyTheAccount",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

`s3:DeleteBucket` is deliberately absent. The bucket carries
`prevent_destroy = true`, and removing it should be a considered manual act.

## 2. State backend

Every stack other than bootstrap reads and writes state in that bucket. Locking
uses the S3 backend's `use_lockfile`, which writes a `.tflock` object beside the
state — there is no DynamoDB table, and so no DynamoDB permissions.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListTheStateBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::lizard-tfstate-000000000000"
    },
    {
      "Sid": "ReadWriteStateAndLock",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::lizard-tfstate-000000000000/billing-alarm/terraform.tfstate",
        "arn:aws:s3:::lizard-tfstate-000000000000/billing-alarm/terraform.tfstate.tflock"
      ]
    }
  ]
}
```

`s3:DeleteObject` on the lock key is required to *release* a lock. Without it
every apply leaves a stale lock behind and the next run blocks.

## 3. The billing-alarm stack

Creating the alarm, runbook, rule, and two IAM roles.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudControlApiItself",
      "Effect": "Allow",
      "Action": [
        "cloudcontrol:CancelResourceRequest",
        "cloudcontrol:CreateResource",
        "cloudcontrol:DeleteResource",
        "cloudcontrol:GetResource",
        "cloudcontrol:ListResources",
        "cloudcontrol:UpdateResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TheAlarm",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListTagsForResource",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:TagResource",
        "cloudwatch:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TheRunbook",
      "Effect": "Allow",
      "Action": [
        "ssm:AddTagsToResource",
        "ssm:CreateDocument",
        "ssm:DeleteDocument",
        "ssm:DescribeDocument",
        "ssm:GetDocument",
        "ssm:ListTagsForResource",
        "ssm:RemoveTagsFromResource",
        "ssm:UpdateDocument",
        "ssm:UpdateDocumentDefaultVersion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TheEventRule",
      "Effect": "Allow",
      "Action": [
        "events:DeleteRule",
        "events:DescribeRule",
        "events:ListTagsForResource",
        "events:ListTargetsByRule",
        "events:PutRule",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:TagResource",
        "events:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TheTwoRoles",
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
    },
    {
      "Sid": "IdentifyTheAccount",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

### Why the IAM statement deserves a second look

This is the one that matters. Creating IAM roles with inline policies is a
privilege-escalation surface: a principal that can call `iam:PutRolePolicy` on an
arbitrary role can grant itself anything.

The `Resource` above is narrowed to role names the module produces
(`*-stop-ec2-automation`, `*-stop-ec2-invocation`). Widening it to `*` hands the
deploying principal effective IAM administrator rights on the account. If your
organisation uses permissions boundaries, apply one and add an
`iam:PermissionsBoundary` condition here.

### `iam:PassRole` is needed by *you*, not just by EventBridge

`PassInvocationRoleToEventBridge` is easy to miss, because the module already
grants EventBridge its own `PassRole` for handing the automation role to SSM at
runtime. That is a different thing.

Creating the rule attaches `role_arn` to the target, and handing a role to a
service is itself a privileged act — so the **deploying principal** needs
`iam:PassRole` for the invocation role. Without it the apply fails at
`awscc_events_rule`, *after* both roles have already been created, leaving a
half-applied stack: roles and runbook present, no rule, nothing wired up.

The condition restricts it to EventBridge, so this grant cannot be reused to
hand those roles to any other service.

Note that `Resource` on the other statements is `*`. Most of these actions are
either create-time (no ARN exists yet to scope against) or list operations that
do not accept a resource. That is a real limitation, not an oversight.

## Check what you have; do not infer it from a name

The AWS managed `PowerUserAccess` policy allows everything **except** `iam:*`,
`organizations:*`, and `account:*`. On its own it can deploy the bootstrap stack,
which is pure S3, but not the alarm stack, which creates two IAM roles.

**An Identity Center permission set named `PowerUserAccess` does not necessarily
grant only that policy.** The assumed-role name (`AWSReservedSSO_PowerUserAccess_…`)
reflects what the set was *called*, not what is attached. Reasoning from it has
already produced one wrong prediction against this repository.

Ask IAM directly:

```bash
ARN=$(aws sts get-caller-identity --query Arn --output text)
aws iam simulate-principal-policy \
  --policy-source-arn "$(echo "$ARN" | sed 's#:sts:#:iam:#; s#assumed-role/#role/#; s#/[^/]*$##')" \
  --action-names iam:CreateRole iam:PutRolePolicy iam:PassRole \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text
```

`allowed` on all three means the alarm stack can be applied.

## One SSM action, three resource ARNs

Not a deploy permission, but the same class of trap and it cost two failed
runs. `ssm:StartAutomationExecution` is authorised against **three** distinct
resources:

| ARN form | What it is |
| --- | --- |
| `document/<name>` | the runbook as a document |
| `automation-definition/<name>` | the runbook as an EventBridge target names it |
| `automation-execution/*` | the execution being created |

Granting only one produces `AccessDenied` naming a resource your policy never
mentions, and fixing that reveals the next. The module now grants all three; see
`terraform/modules/billing-alarm-stop-ec2/iam.tf`.

## Verification status

Both stacks **have now been applied successfully** to a real account, so the
resources and actions listed here are real rather than guessed.

They are still **not proven minimal**. The applies ran with an Identity Center
role carrying `PowerUserAccess` plus full IAM, not with the policies on this
page, so nothing here has been tested as a least-privilege set — it may be
missing actions, or contain some that are unnecessary.

If you deploy with exactly these policies, please record what breaks. Cloud
Control surfaces failures as `AccessDenied` naming the underlying service action,
which makes them straightforward to add. Its operations are asynchronous and the
provider polls, so if denials appear during polling, add
`cloudcontrol:GetResourceRequestStatus`.
