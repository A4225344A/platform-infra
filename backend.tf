terraform {
  backend "s3" {
    bucket         = "platform-tfstate-029099141993"
    key            = "platform/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "platform-tflock"
    encrypt        = true
  }
}
