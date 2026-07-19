provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "Lizard"
      ManagedBy = "Terraform"
      Stack     = "billing-alarm"
    }
  }
}
