# `terraform/bootstrap` — example plan output

What applying the bootstrap stack creates, so reviewers can see the shape of it
without needing AWS credentials.

- Generated from commit `eb59405` with Terraform v1.15.8
- **The AWS account ID is redacted** and replaced with `000000000000`, which is
  also the placeholder used in `backend.hcl.example`. The real bucket name is
  `lizard-tfstate-<your-account-id>`, derived from `aws_caller_identity` so it
  is globally unique without anyone having to choose a name.
- Plans go stale. Treat this as illustrative, not as a guarantee of what your
  own apply will do.

## What to look for

| Property | Why it matters |
| --- | --- |
| `prevent_destroy` on the bucket | State must outlive a `terraform destroy` aimed at this stack |
| `versioning_configuration.status = "Enabled"` | The only thing making a corrupted state recoverable |
| `sse_algorithm = "AES256"` | Encryption at rest |
| All four public-access-block flags `true` | State is plain text and routinely contains secrets |
| `noncurrent_days = 30` | Superseded versions expire rather than accumulating forever |
| Bucket policy denying `aws:SecureTransport = false` | Rejects any non-TLS request |

No DynamoDB table appears, and that is deliberate: locking uses the S3 backend's
`use_lockfile`, which locks via conditional writes.

## Plan

```text
data.aws_caller_identity.current: Reading...
data.aws_caller_identity.current: Read complete after 0s [id=000000000000]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create
 <= read (data resources)

Terraform will perform the following actions:

  # data.aws_iam_policy_document.state will be read during apply
  # (config refers to values not yet known)
 <= data "aws_iam_policy_document" "state" {
      + id            = (known after apply)
      + json          = (known after apply)
      + minified_json = (known after apply)

      + statement {
          + actions   = [
              + "s3:*",
            ]
          + effect    = "Deny"
          + resources = [
              + (known after apply),
              + (known after apply),
            ]
          + sid       = "DenyInsecureTransport"

          + condition {
              + test     = "Bool"
              + values   = [
                  + "false",
                ]
              + variable = "aws:SecureTransport"
            }

          + principals {
              + identifiers = [
                  + "*",
                ]
              + type        = "*"
            }
        }
    }

  # aws_s3_bucket.state will be created
  + resource "aws_s3_bucket" "state" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = "lizard-tfstate-000000000000"
      + bucket_domain_name          = (known after apply)
      + bucket_namespace            = (known after apply)
      + bucket_prefix               = (known after apply)
      + bucket_region               = (known after apply)
      + bucket_regional_domain_name = (known after apply)
      + force_destroy               = false
      + hosted_zone_id              = (known after apply)
      + id                          = (known after apply)
      + object_lock_enabled         = (known after apply)
      + policy                      = (known after apply)
      + region                      = "us-east-1"
      + request_payer               = (known after apply)
      + tags_all                    = {
          + "ManagedBy" = "Terraform"
          + "Project"   = "Lizard"
          + "Stack"     = "bootstrap"
        }
      + website_domain              = (known after apply)
      + website_endpoint            = (known after apply)

      + cors_rule (known after apply)

      + grant (known after apply)

      + lifecycle_rule (known after apply)

      + logging (known after apply)

      + object_lock_configuration (known after apply)

      + replication_configuration (known after apply)

      + server_side_encryption_configuration (known after apply)

      + versioning (known after apply)

      + website (known after apply)
    }

  # aws_s3_bucket_lifecycle_configuration.state will be created
  + resource "aws_s3_bucket_lifecycle_configuration" "state" {
      + bucket                                 = (known after apply)
      + expected_bucket_owner                  = (known after apply)
      + id                                     = (known after apply)
      + region                                 = "us-east-1"
      + transition_default_minimum_object_size = "all_storage_classes_128K"

      + rule {
          + id     = "expire-noncurrent-state-versions"
          + status = "Enabled"
            # (1 unchanged attribute hidden)

          + abort_incomplete_multipart_upload {
              + days_after_initiation = 7
            }

          + filter {
                # (1 unchanged attribute hidden)
            }

          + noncurrent_version_expiration {
              + noncurrent_days = 30
            }
        }
    }

  # aws_s3_bucket_policy.state will be created
  + resource "aws_s3_bucket_policy" "state" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + policy = (known after apply)
      + region = "us-east-1"
    }

  # aws_s3_bucket_public_access_block.state will be created
  + resource "aws_s3_bucket_public_access_block" "state" {
      + block_public_acls       = true
      + block_public_policy     = true
      + bucket                  = (known after apply)
      + id                      = (known after apply)
      + ignore_public_acls      = true
      + region                  = "us-east-1"
      + restrict_public_buckets = true
    }

  # aws_s3_bucket_server_side_encryption_configuration.state will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "us-east-1"

      + rule {
          + blocked_encryption_types = (known after apply)
          + bucket_key_enabled       = (known after apply)

          + apply_server_side_encryption_by_default {
              + kms_master_key_id = (known after apply)
              + sse_algorithm     = "AES256"
            }
        }
    }

  # aws_s3_bucket_versioning.state will be created
  + resource "aws_s3_bucket_versioning" "state" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "us-east-1"

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

Plan: 6 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + backend_hcl      = <<-EOT
        bucket = "lizard-tfstate-000000000000"
        region = "us-east-1"
    EOT
  + state_bucket     = "lizard-tfstate-000000000000"
  + state_bucket_arn = (known after apply)

─────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```
