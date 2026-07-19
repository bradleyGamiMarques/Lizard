# Custom Automation runbook rather than AWS-StopEC2Instance.
#
# SSM can target by tag natively, but only through the Targets and
# TargetParameterName arguments of StartAutomationExecution. Those are top-level
# API parameters, and an EventBridge target's Input populates a document's
# Parameters only — so tag targeting cannot reach SSM through EventBridge. The
# lookup therefore has to happen inside the document.
#
# Two declarative aws:executeAwsApi steps, no embedded script, so the whole
# remediation is reviewable as data.
#
# If no instance carries the tag, step two fails: the EC2 StopInstances API
# rejects an empty InstanceIds list, and aws:branch has no operation that can
# test a list for emptiness. That failure is deliberate and left visible — it
# means the alarm fired while Lizard had nothing it was permitted to stop, which
# is worth surfacing rather than reporting as a successful remediation.

locals {
  document_name = "${var.name}-stop-tagged-ec2"

  document_content = {
    schemaVersion = "0.3"
    description   = "Stops running EC2 instances tagged ${var.stoppable_tag_key}=${var.stoppable_tag_value}."
    assumeRole    = "{{ AutomationAssumeRole }}"

    parameters = {
      AutomationAssumeRole = {
        type        = "String"
        description = "Role SSM assumes to run this document. Supplied by the EventBridge target."
      }
    }

    mainSteps = [
      {
        name        = "findStoppableInstances"
        action      = "aws:executeAwsApi"
        description = "Find running instances carrying the stoppable tag."

        inputs = {
          Service = "ec2"
          Api     = "DescribeInstances"
          Filters = [
            {
              Name   = "tag:${var.stoppable_tag_key}"
              Values = [var.stoppable_tag_value]
            },
            {
              # Stopping an already-stopped instance is a no-op that only adds
              # failure noise, and pending/shutting-down instances cannot be
              # stopped at all.
              Name   = "instance-state-name"
              Values = ["running"]
            },
          ]
        }

        outputs = [
          {
            Name     = "InstanceIds"
            Selector = "$.Reservations..Instances..InstanceId"
            Type     = "StringList"
          },
        ]
      },
      {
        name        = "stopInstances"
        action      = "aws:executeAwsApi"
        description = "Stop every instance found by the previous step."

        inputs = {
          Service     = "ec2"
          Api         = "StopInstances"
          InstanceIds = "{{ findStoppableInstances.InstanceIds }}"
        }
      },
    ]
  }
}

resource "awscc_ssm_document" "stop_tagged_ec2" {
  name            = local.document_name
  document_type   = "Automation"
  document_format = "JSON"
  content         = jsonencode(local.document_content)

  tags = local.tags
}
