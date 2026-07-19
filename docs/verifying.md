# Verifying Lizard against a real AWS account

Everything in this repository is verified by `terraform validate`, `tflint`, and
mocked unit tests. None of that proves the chain actually works: mocks confirm
shape and typing, not that EventBridge delivers to SSM or that the runbook's
JSONPath selector returns instance IDs in the form `StopInstances` accepts.

This page is the procedure for finding out. **It stops real EC2 instances and
spends real money.**

## Read this before starting

- **Use throwaway instances.** The remediation genuinely stops whatever carries
  the tag. Never run this against anything you care about.
- **A big instance does not speed the test up.** `EstimatedCharges` publishes
  roughly every six hours, so metric latency dominates, not how quickly you reach
  the threshold. An `m5.24xlarge` crosses $0.50 in about seven minutes and then
  bills ~$4.60/hour while you wait — roughly $28 for nothing. A `t3.micro` at
  ~$0.01/hour proves the same thing.
- **You probably do not need to generate spend at all.** AWS puts an alarm into
  `ALARM` immediately if charges already exceed the threshold at creation time.
  Month-to-date EC2 spend in an account with any activity is already above $0.50.
- **The bucket outlives `terraform destroy`.** The bootstrap stack sets
  `prevent_destroy`. Removing it is a deliberate manual act.
- **Billing alerts take ~15 minutes** to start publishing after you enable them.

## Phase 0 — prerequisites

1. Enable **Receive CloudWatch Billing Alerts** in the payer account, under
   Billing and Cost Management → Billing Preferences. Nothing works without this
   and the failure is silent: the alarm simply sits in `INSUFFICIENT_DATA`.
2. Grant your identity the permissions in [permissions.md](permissions.md).
3. Confirm billing data is actually flowing before going further:

   ```bash
   aws cloudwatch list-metrics \
     --namespace AWS/Billing --metric-name EstimatedCharges \
     --region us-east-1
   ```

   Empty output means step 1 has not taken effect yet. Wait, do not proceed.

4. Note your current month-to-date EC2 charges, so you can pick a threshold below
   them:

   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Billing --metric-name EstimatedCharges \
     --dimensions Name=ServiceName,Value=AmazonEC2 Name=Currency,Value=USD \
     --start-time "$(date -u -v-12H '+%Y-%m-%dT%H:%M:%SZ')" \
     --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
     --period 21600 --statistics Maximum --region us-east-1
   ```

## Phase 1 — bootstrap the state bucket

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
terraform -chdir=terraform/bootstrap output backend_hcl
```

**What to check.** The apply succeeds, and the output prints a `bucket` and
`region` pair. This is also the first real test of
[permissions.md](permissions.md) — record any `AccessDenied` and the action it
names.

## Phase 2 — launch two instances, tag one

Do this **before** deploying, not after.

If month-to-date spend for the service already exceeds your threshold — which it
usually does, since the metric is a running monthly total — the alarm enters
`ALARM` the moment it is created. Deploy first and that firing lands on an empty
target set, so the automation fails with a zero-match error and your first result
looks like a broken module when it is the documented behaviour.

Launch two throwaway instances and tag only one. Tagging just one is the point:
it checks the permission boundary as well as the action.

```bash
# Tagged — expected to be stopped
aws ec2 run-instances --image-id ami-xxxxxxxx --instance-type t3.micro \
  --region us-east-1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=StoppableBy,Value=Lizard},{Key=Name,Value=lizard-test-tagged}]'

# Untagged — expected to survive
aws ec2 run-instances --image-id ami-xxxxxxxx --instance-type t3.micro \
  --region us-east-1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lizard-test-untagged}]'
```

Wait for both to reach `running` — the runbook filters on that state, so a
`pending` instance is skipped.

## Phase 3 — deploy the alarm and remediation

State lives in the bucket created by Phase 1, so it survives losing your laptop.

```bash
cd terraform/examples/stop-tagged-ec2
cp backend.hcl.example backend.hcl     # fill in from the Phase 1 output
terraform init -backend-config=backend.hcl
terraform apply -var 'threshold_usd=0.50'
```

**What to check.**

- The apply succeeds. `awscc` resources exercise the Cloud Control API, so this
  is where a missing `cloudcontrol:*` action surfaces.
- The alarm exists and its state is meaningful:

  ```bash
  aws cloudwatch describe-alarms \
    --alarm-names "$(terraform output -raw alarm_name)" \
    --region us-east-1 --query 'MetricAlarms[0].[StateValue,StateReason]'
  ```

  `INSUFFICIENT_DATA` here means billing data is not flowing — go back to
  Phase 0. If month-to-date EC2 spend already exceeds $0.50, expect `ALARM`.

## Phase 4 — force the alarm

If the alarm already fired on deployment, Phase 3 has told you most of what
Phase 4 would. Force it anyway: `set-alarm-state` is repeatable and gives you a
clean run to observe from the start.

Forcing the state emits a genuine `CloudWatch Alarm State Change` event, so
EventBridge and SSM behave exactly as they would in production.

Note that EventBridge fires on the *transition* into `ALARM`. An alarm already
sitting in `ALARM` will not re-fire, so set it to `OK` first if you need a second
run:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name "$(terraform output -raw alarm_name)" \
  --state-value OK --state-reason "Reset before re-test" \
  --region us-east-1
```

```bash
aws cloudwatch set-alarm-state \
  --alarm-name "$(terraform output -raw alarm_name)" \
  --state-value ALARM \
  --state-reason "Verifying Lizard remediation" \
  --region us-east-1
```

**What to check, in order.**

1. An automation execution started at all — this proves EventBridge accepted the
   SSM target ARN and `Input` shape:

   ```bash
   aws ssm describe-automation-executions \
     --filters Key=DocumentNamePrefix,Values="$(terraform output -raw document_name)" \
     --region us-east-1
   ```

   Nothing here means the event did not route. Check the rule's metrics for
   `FailedInvocations`.

2. The execution **succeeded**. A failure at `stopInstances` with an empty
   parameter means the JSONPath selector
   `$.Reservations..Instances..InstanceId` did not return IDs in the shape
   `StopInstances` wants — the single most likely defect in this repository.

   ```bash
   aws ssm get-automation-execution \
     --automation-execution-id <id> --region us-east-1 \
     --query 'AutomationExecution.StepExecutions[].[StepName,StepStatus,FailureMessage]'
   ```

3. **The tagged instance is stopping or stopped.**
4. **The untagged instance is still running.** This is the permission boundary
   working. If it stopped too, the `ec2:ResourceTag` condition is not doing what
   the module claims and that is a serious finding.

```bash
aws ec2 describe-instances --region us-east-1 \
  --filters 'Name=tag:Name,Values=lizard-test-*' \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`StoppableBy`].Value|[0]]' \
  --output table
```

The alarm returns to its real state at the next evaluation.

## Phase 5 — optional, prove the alarm itself

Phase 4 verifies everything downstream of the alarm but not the alarm's own
trigger. To close that gap, set a threshold below current month-to-date EC2 spend
and wait for a real evaluation — up to six hours. Re-tag an instance first, since
Phase 4 already stopped the previous one.

Note that EventBridge fires on the *transition* into `ALARM`. Once the alarm is
in `ALARM` it will not fire again until it returns to `OK`, so an instance tagged
afterwards is not stopped.

## Teardown

```bash
aws ec2 terminate-instances --instance-ids i-... i-... --region us-east-1
terraform destroy -var 'threshold_usd=0.50'
```

Leaving the alarm in place with a $0.50 threshold means it stays in `ALARM` for
the rest of the month.

The state bucket survives `terraform destroy` by design. Remove
`prevent_destroy` from `terraform/bootstrap/main.tf` first if you genuinely want
it gone.

## Record the results

Update this table, and correct [permissions.md](permissions.md) with anything a
real apply turned up. The value of this exercise is the claims it *disproves*.

| Claim | Verified? | Notes |
| --- | --- | --- |
| Billing data is published for this account | **yes** | `get-metric-statistics` returned a datapoint |
| Bootstrap stack applies | **yes** | 6 resources created |
| Bucket has versioning enabled | **yes** | `Status: Enabled` |
| Bucket is encrypted with AES256 | **yes** | confirmed via `get-bucket-encryption` |
| All four public-access-block flags set | **yes** | all `true` |
| Noncurrent versions expire after 30 days | **yes** | lifecycle rule active |
| Bucket policy **rejects** non-TLS requests | **yes** | an HTTP request returned `AccessDenied` with an explicit deny from the resource policy |
| Alarm stack plans cleanly | **yes** | 6 to add; region guard precondition passed |
| Alarm stack applies | **yes** | 6 resources created |
| Alarm reaches `ALARM` on real spend | **yes** | `19.35 > 0.5`, unforced |
| EventBridge matches the alarm event | **yes** | `MatchedEvents` incremented |
| EventBridge accepts the automation-definition ARN and `Input` | **yes** | after the IAM fix below |
| JSONPath selector returns IDs `StopInstances` accepts | **yes** | `$.Reservations..Instances..InstanceId` worked — the prediction that it would fail was wrong |
| **Tagged instance is stopped** | **yes** | `lizard-test-tagged` → `stopping` |
| **Untagged instance is not stopped** | **yes** | `lizard-test-untagged` stayed `running`; the tag boundary holds |
| Permissions in `permissions.md` are minimal and sufficient | **no — untested** | applied with `PowerUserAccess` plus full IAM, not these policies |
| `PowerUserAccess` alone suffices | **n/a** | the permission set carried more than its name implied; predicting from the name was wrong |
| Zero-match run fails as documented | not yet | never exercised — an instance was always tagged |

### What a real apply caught that mocks did not

**`ssm:StartAutomationExecution` authorises against three resource ARNs**, not
one. The module granted only `automation-definition/<name>`; the call is also
checked against `document/<name>` and `automation-execution/*`. Each fix revealed
the next denial. Twenty unit tests stayed green throughout, because they asserted
the policy contained the ARN form that had been assumed correct.

**The first event fired mid-apply.** `MatchedEvents=1` with `Invocations=0`: the
alarm entered `ALARM` as soon as it was created and emitted before `PutTargets`
completed. The ordering hazard is not only "nothing tagged yet" but "target not
yet wired". EventBridge fires on the *transition*, so re-testing needs an
`OK` → `ALARM` cycle rather than setting `ALARM` again.
