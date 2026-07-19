# Unit tests. Both providers are mocked, so these run with no AWS credentials
# and create nothing.
#
# Assertions here are written to fail under mutation: every property they claim
# to check has been verified to break at least one test when deliberately
# changed. An assertion that cannot fail is worse than no assertion, because it
# reports confidence it has not earned.

mock_provider "awscc" {}

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  threshold_usd = 50
  service_name  = "AmazonEC2"
}

# ---------------------------------------------------------------------------
# Alarm
# ---------------------------------------------------------------------------

run "alarm_watches_the_billing_metric" {
  command = apply

  assert {
    condition     = awscc_cloudwatch_alarm.this.namespace == "AWS/Billing"
    error_message = "Alarm must watch the AWS/Billing namespace."
  }

  assert {
    condition     = awscc_cloudwatch_alarm.this.metric_name == "EstimatedCharges"
    error_message = "Alarm must watch the EstimatedCharges metric."
  }

  assert {
    condition     = awscc_cloudwatch_alarm.this.statistic == "Maximum"
    error_message = "EstimatedCharges is a month-to-date running total, so only Maximum reflects the current bill."
  }

  assert {
    condition     = awscc_cloudwatch_alarm.this.comparison_operator == "GreaterThanThreshold"
    error_message = "Alarm must fire strictly above the threshold."
  }

  assert {
    condition     = awscc_cloudwatch_alarm.this.threshold == 50
    error_message = "threshold_usd must reach the alarm unchanged."
  }
}

# period and evaluation_periods are asserted separately and by distinct values,
# so transposing the two arguments fails rather than passing silently.
run "alarm_period_and_evaluation_periods_are_not_transposed" {
  command = apply

  variables {
    period_seconds     = 43200
    evaluation_periods = 2
  }

  assert {
    condition     = awscc_cloudwatch_alarm.this.period == 43200
    error_message = "period must carry period_seconds, not evaluation_periods."
  }

  assert {
    condition     = awscc_cloudwatch_alarm.this.evaluation_periods == 2
    error_message = "evaluation_periods must carry evaluation_periods, not period_seconds."
  }
}

run "alarm_does_not_fire_on_missing_billing_data" {
  command = apply

  assert {
    condition     = awscc_cloudwatch_alarm.this.treat_missing_data == "missing"
    error_message = "Missing billing datapoints must retain state; breaching would stop instances on absent data."
  }
}

run "alarm_is_scoped_to_the_named_service" {
  command = apply

  assert {
    condition     = length(awscc_cloudwatch_alarm.this.dimensions) == 2
    error_message = "A service-scoped alarm must carry exactly Currency and ServiceName."
  }

  assert {
    condition     = contains([for d in awscc_cloudwatch_alarm.this.dimensions : "${d.name}=${d.value}"], "ServiceName=AmazonEC2")
    error_message = "service_name must reach the ServiceName dimension."
  }

  assert {
    condition     = contains([for d in awscc_cloudwatch_alarm.this.dimensions : "${d.name}=${d.value}"], "Currency=USD")
    error_message = "Currency dimension must be USD, the only currency AWS publishes."
  }
}

run "alarm_covers_the_whole_account_when_no_service_given" {
  command = apply

  variables {
    service_name = null
  }

  assert {
    condition     = length(awscc_cloudwatch_alarm.this.dimensions) == 1
    error_message = "An account-wide alarm must carry only the Currency dimension."
  }

  assert {
    condition     = one(awscc_cloudwatch_alarm.this.dimensions).name == "Currency"
    error_message = "The single dimension of an account-wide alarm must be Currency."
  }
}

# ---------------------------------------------------------------------------
# Event rule
# ---------------------------------------------------------------------------

run "rule_matches_only_this_alarm_entering_alarm_state" {
  command = apply

  assert {
    condition     = jsondecode(awscc_events_rule.this.event_pattern)["source"] == ["aws.cloudwatch"]
    error_message = "Rule must match events from aws.cloudwatch."
  }

  assert {
    condition     = jsondecode(awscc_events_rule.this.event_pattern)["detail-type"] == ["CloudWatch Alarm State Change"]
    error_message = "Rule must match CloudWatch Alarm State Change events."
  }

  # Without this narrowing, any alarm in the account entering ALARM would stop
  # instances.
  assert {
    condition     = jsondecode(awscc_events_rule.this.event_pattern)["detail"]["alarmName"] == [awscc_cloudwatch_alarm.this.alarm_name]
    error_message = "Rule must be scoped to this module's alarm by name."
  }

  assert {
    condition     = jsondecode(awscc_events_rule.this.event_pattern)["detail"]["state"]["value"] == ["ALARM"]
    error_message = "Rule must fire only on ALARM; matching OK would stop instances on recovery."
  }
}

run "rule_targets_the_versioned_automation_definition" {
  command = apply

  assert {
    condition     = one(awscc_events_rule.this.targets).arn == "arn:aws:ssm:us-east-1:123456789012:automation-definition/lizard-stop-tagged-ec2:$DEFAULT"
    error_message = "EventBridge needs the full automation-definition ARN including a version suffix."
  }

  assert {
    condition     = jsondecode(one(awscc_events_rule.this.targets).input)["AutomationAssumeRole"] == [awscc_iam_role.automation.arn]
    error_message = "Target input must pass the automation role as a single-element list, which is the shape SSM requires."
  }

  assert {
    condition     = one(awscc_events_rule.this.targets).role_arn == awscc_iam_role.invocation.arn
    error_message = "The rule must invoke using the invocation role, not the automation role."
  }
}

# ---------------------------------------------------------------------------
# IAM — the tag is a permission boundary, so these are the load-bearing tests
# ---------------------------------------------------------------------------

run "stop_permission_is_conditioned_on_the_tag" {
  command = apply

  assert {
    condition = try(
      [for s in jsondecode(one(awscc_iam_role.automation.policies).policy_document)["Statement"] :
      s if s["Sid"] == "StopOnlyTaggedInstances"][0]["Condition"]["StringEquals"]["ec2:ResourceTag/StoppableBy"],
      null
    ) == "Lizard"
    error_message = "ec2:StopInstances must be conditioned on the stoppable tag, otherwise any instance in the account can be stopped."
  }
}

run "tag_condition_follows_a_custom_tag" {
  command = apply

  variables {
    stoppable_tag_key   = "KillSwitch"
    stoppable_tag_value = "Enabled"
  }

  assert {
    condition = try(
      [for s in jsondecode(one(awscc_iam_role.automation.policies).policy_document)["Statement"] :
      s if s["Sid"] == "StopOnlyTaggedInstances"][0]["Condition"]["StringEquals"]["ec2:ResourceTag/KillSwitch"],
      null
    ) == "Enabled"
    error_message = "A custom tag key and value must flow into the IAM condition, or the boundary and the runbook disagree."
  }

  assert {
    condition     = strcontains(awscc_ssm_document.stop_tagged_ec2.content, "tag:KillSwitch")
    error_message = "The runbook filter must use the same tag key as the IAM condition."
  }
}

# Regression test for a real AccessDenied observed against AWS.
#
# A runbook is addressable as both an automation-definition and a document. The
# EventBridge target needs the former; IAM authorises StartAutomationExecution
# against the latter. Granting only the automation-definition form fails at
# runtime with an error naming a resource the policy never mentions — invisible
# to every other assertion here, because they all encoded the same wrong
# assumption.
run "start_permission_covers_the_document_arn_form" {
  command = apply

  assert {
    condition = anytrue([
      for r in try(
        [for s in jsondecode(one(awscc_iam_role.invocation.policies).policy_document)["Statement"] :
        s if s["Sid"] == "StartThisAutomationOnly"][0]["Resource"],
        []
      ) : strcontains(r, ":document/lizard-stop-tagged-ec2")
    ])
    error_message = "ssm:StartAutomationExecution must be granted on the document ARN; IAM authorises against that form, not automation-definition."
  }

  assert {
    condition = anytrue([
      for r in try(
        [for s in jsondecode(one(awscc_iam_role.invocation.policies).policy_document)["Statement"] :
        s if s["Sid"] == "StartThisAutomationOnly"][0]["Resource"],
        []
      ) : strcontains(r, ":automation-definition/lizard-stop-tagged-ec2")
    ])
    error_message = "The automation-definition ARN form must also be granted, since that is what the EventBridge target names."
  }
}

run "eventbridge_never_holds_the_destructive_permission" {
  command = apply

  assert {
    condition     = !strcontains(one(awscc_iam_role.invocation.policies).policy_document, "ec2:StopInstances")
    error_message = "The invocation role must not be able to stop instances directly."
  }

  assert {
    condition = try(
      [for s in jsondecode(one(awscc_iam_role.invocation.policies).policy_document)["Statement"] :
      s if s["Sid"] == "PassAutomationRoleToSsm"][0]["Condition"]["StringEquals"]["iam:PassedToService"],
      null
    ) == "ssm.amazonaws.com"
    error_message = "PassRole must be restricted to SSM, otherwise the role can be handed to any service."
  }
}

run "roles_trust_only_their_own_service_principal" {
  command = apply

  assert {
    condition = try(
      jsondecode(awscc_iam_role.automation.assume_role_policy_document)["Statement"][0]["Principal"]["Service"],
      null
    ) == "ssm.amazonaws.com"
    error_message = "The automation role must be assumable only by SSM."
  }

  assert {
    condition = try(
      jsondecode(awscc_iam_role.invocation.assume_role_policy_document)["Statement"][0]["Principal"]["Service"],
      null
    ) == "events.amazonaws.com"
    error_message = "The invocation role must be assumable only by EventBridge."
  }
}

# ---------------------------------------------------------------------------
# Runbook
# ---------------------------------------------------------------------------

run "runbook_filters_by_tag_and_running_state" {
  command = apply

  assert {
    condition     = jsondecode(awscc_ssm_document.stop_tagged_ec2.content)["mainSteps"][0]["inputs"]["Filters"][0]["Name"] == "tag:StoppableBy"
    error_message = "The lookup step must filter on the stoppable tag."
  }

  assert {
    condition     = jsondecode(awscc_ssm_document.stop_tagged_ec2.content)["mainSteps"][0]["inputs"]["Filters"][1]["Values"] == ["running"]
    error_message = "Only running instances should be selected; stopping a stopped instance is failure noise."
  }

  assert {
    condition     = jsondecode(awscc_ssm_document.stop_tagged_ec2.content)["mainSteps"][1]["inputs"]["Api"] == "StopInstances"
    error_message = "The second step must stop, not terminate — terminate is irreversible."
  }

  assert {
    condition     = !strcontains(awscc_ssm_document.stop_tagged_ec2.content, "TerminateInstances")
    error_message = "This module must never call TerminateInstances."
  }
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

run "rejects_a_zero_threshold" {
  command = plan

  variables {
    threshold_usd = 0
  }

  expect_failures = [var.threshold_usd]
}

run "rejects_a_period_shorter_than_the_publish_interval" {
  command = plan

  variables {
    period_seconds = 300
  }

  expect_failures = [var.period_seconds]
}

run "rejects_fractional_evaluation_periods" {
  command = plan

  variables {
    evaluation_periods = 1.5
  }

  expect_failures = [var.evaluation_periods]
}

run "rejects_an_empty_tag_key" {
  command = plan

  variables {
    stoppable_tag_key = ""
  }

  expect_failures = [var.stoppable_tag_key]
}

# The failure this guards against is a plausible typo, not a nonsense string.
# "AmazonEc2" is alphanumeric and looks right, so the previous shape-only check
# accepted it — producing an alarm that receives no data and never fires.
run "rejects_a_plausible_service_name_typo" {
  command = plan

  variables {
    service_name = "AmazonEc2"
  }

  expect_failures = [var.service_name]
}

run "rejects_a_display_name_instead_of_a_billing_name" {
  command = plan

  variables {
    service_name = "EC2"
  }

  expect_failures = [var.service_name]
}

# A different real service name is rejected, not because it is invalid to AWS,
# but because it is incoherent here: this module stops EC2 instances, so watching
# RDS spend and then stopping EC2 boxes is a config that reads sensibly and does
# the wrong thing.
run "rejects_a_service_this_module_cannot_act_on" {
  command = plan

  variables {
    service_name = "AmazonRDS"
  }

  expect_failures = [var.service_name]
}
