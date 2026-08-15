terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
  backend "s3" {
    bucket         = "platform-tfstate-029099141993"
    key            = "oidc/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "platform-tflock"
    encrypt        = true
  }
}
provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = { project = var.project_name, managedBy = "terraform", layer = "oidc-bootstrap" }
  }
}
