terraform {
  required_version = ">= 1.10"

  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.93"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55"
    }
  }

  # No backend. This is an example meant to be copied into a real stack, which
  # brings its own state configuration.
}

# Both providers are pinned to us-east-1. AWS publishes the AWS/Billing
# namespace only there, and the module's precondition fails the plan anywhere
# else rather than creating an alarm that never receives data.
provider "aws" {
  region = "us-east-1"
}

provider "awscc" {
  region = "us-east-1"
}
