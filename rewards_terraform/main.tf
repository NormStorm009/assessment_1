terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backnd block = local state (terraform.tfstate in your working directory)
  
}

data "aws_caller_identity" "current" {}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}