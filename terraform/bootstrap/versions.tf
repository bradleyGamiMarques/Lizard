terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55"
    }
  }

  # No backend block on purpose. This stack creates the bucket that every other
  # stack stores its state in, so it cannot store its own state there. Its state
  # stays local and is gitignored.
}
