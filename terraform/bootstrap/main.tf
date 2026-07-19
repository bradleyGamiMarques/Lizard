# Bootstrap stack — creates the S3 bucket that every other stack keeps its state
# in. Run this once per AWS account, before initialising any other stack:
#
#   terraform -chdir=terraform/bootstrap init
#   terraform -chdir=terraform/bootstrap apply
#   terraform -chdir=terraform/bootstrap output backend_hcl
#
# State locking is handled by the S3 backend's `use_lockfile`, which uses S3
# conditional writes. No DynamoDB table is needed.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "Lizard"
      ManagedBy = "Terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = coalesce(
    var.state_bucket_name,
    "lizard-tfstate-${data.aws_caller_identity.current.account_id}",
  )
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # A state bucket must outlive any `terraform destroy` aimed at this stack.
  # Removing this guard is a deliberate, manual act.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is what makes a truncated or corrupted state recoverable. Without
# it, a bad apply overwrites the only copy.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Superseded state versions accumulate on every apply and are never cleaned up
# on their own.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Terraform state is plain text and routinely contains secrets. Refuse any
# request that is not over TLS.
data "aws_iam_policy_document" "state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  # The public access block must be in place before a bucket policy is attached,
  # otherwise the policy write can race with it.
  depends_on = [aws_s3_bucket_public_access_block.state]
}
