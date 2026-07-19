terraform {
  required_version = ">= 1.10"

  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.93"
    }

    # Used for the caller-identity, region, and partition data sources. awscc
    # has no equivalent, and both the SSM automation-definition ARN and the
    # us-east-1 guard need them.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55"
    }
  }
}
