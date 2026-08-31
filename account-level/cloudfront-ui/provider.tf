terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "platform-tfstate-029099141993"
    key            = "platform/account-level/cloudfront-ui/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "platform-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      project   = var.project_name
      managedBy = "terraform"
      scope     = "account-level"
      task      = "11.5"
    }
  }
}
