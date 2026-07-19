# Partial backend configuration.
#
# `bucket` and `region` are account-specific, so they are supplied at init time
# rather than committed to this public repository:
#
#   cp backend.hcl.example backend.hcl     # then fill in your values
#   terraform init -backend-config=backend.hcl
#
# `terraform -chdir=../bootstrap output backend_hcl` prints the correct values.
#
# `use_lockfile` locks state using S3 conditional writes, which replaces the
# DynamoDB table the S3 backend used to require. There is no lock table to
# create, pay for, or forget to clean up.
terraform {
  backend "s3" {
    key          = "billing-alarm/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
