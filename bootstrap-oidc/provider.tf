terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
  # backend 區塊是 Terraform 語言本身的限制,不能用 var.*/interpolation——
  # 這裡的值只能是字面值,fork 這份程式碼的人要自己把 bucket/dynamodb_table
  # 換成自己 bootstrap.tf(根目錄)apply 出來的實際名稱。
  backend "s3" {
    bucket         = "platform-tfstate-029099141993"
    key            = "oidc/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "platform-tflock"
    encrypt        = true
  }
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { project = var.project_name, managedBy = "terraform", layer = "oidc-bootstrap" }
  }
}
