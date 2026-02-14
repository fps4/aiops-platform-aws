terraform {
  required_version = ">= 1.5.0"

  # Backend configuration for remote state in S3
  # Update the bucket name to: {your-account-id}-aiops-platform-terraform-state
  # Run scripts/bootstrap-terraform-state.sh first to create the bucket
  backend "s3" {
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
