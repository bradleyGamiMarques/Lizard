# Partial backend configuration. bucket and region are account-specific and are
# supplied at init time so they never land in this public repository:
#
#   cp backend.hcl.example backend.hcl     # then fill in your values
#   terraform init -backend-config=backend.hcl
#
# `terraform -chdir=../../bootstrap output backend_hcl` prints them.
#
# This state controls infrastructure that stops EC2 instances. Losing it means
# losing the ability to change or destroy that infrastructure cleanly

terraform {
  backend "s3" {
    key          = "examples/stop-tagged-ec2/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
