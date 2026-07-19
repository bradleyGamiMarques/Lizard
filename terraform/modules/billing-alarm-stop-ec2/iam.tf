# Two roles, deliberately separate.
#
#   automation — assumed by SSM, holds the permission to actually stop instances
#   invocation — assumed by EventBridge, may only start this one document and
#                pass the automation role
#
# Collapsing them would hand EventBridge the destructive permission directly.

resource "awscc_iam_role" "automation" {
  role_name   = "${var.name}-stop-ec2-automation"
  description = "Assumed by SSM Automation to stop instances tagged ${var.stoppable_tag_key}=${var.stoppable_tag_value}."

  assume_role_policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  policies = [{
    policy_name = "stop-tagged-instances"
    policy_document = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          # DescribeInstances is a list operation: it does not accept a resource
          # ARN and cannot be tag-scoped. Read-only, so the exposure is limited
          # to instance metadata.
          Sid      = "FindInstances"
          Effect   = "Allow"
          Action   = "ec2:DescribeInstances"
          Resource = "*"
        },
        {
          # The tag is a permission boundary, not merely a filter. Even if the
          # runbook were wrong or replaced, this role physically cannot stop an
          # instance that does not carry the tag.
          Sid      = "StopOnlyTaggedInstances"
          Effect   = "Allow"
          Action   = "ec2:StopInstances"
          Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/*"
          Condition = {
            StringEquals = {
              "ec2:ResourceTag/${var.stoppable_tag_key}" = var.stoppable_tag_value
            }
          }
        },
      ]
    })
  }]

  tags = local.tags
}

resource "awscc_iam_role" "invocation" {
  role_name   = "${var.name}-stop-ec2-invocation"
  description = "Assumed by EventBridge to start the ${local.document_name} automation."

  assume_role_policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  policies = [{
    policy_name = "start-stop-ec2-automation"
    policy_document = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "StartThisAutomationOnly"
          Effect   = "Allow"
          Action   = "ssm:StartAutomationExecution"
          Resource = "${local.automation_definition_arn_base}:*"
        },
        {
          # StartAutomationExecution fails without this: EventBridge must be able
          # to hand the automation role to SSM. Scoped to that one role, and
          # further to SSM as the consuming service.
          Sid      = "PassAutomationRoleToSsm"
          Effect   = "Allow"
          Action   = "iam:PassRole"
          Resource = awscc_iam_role.automation.arn
          Condition = {
            StringEquals = {
              "iam:PassedToService" = "ssm.amazonaws.com"
            }
          }
        },
      ]
    })
  }]

  tags = local.tags
}
