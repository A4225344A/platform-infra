# 這個檔案是動態產生的(bootstrap.tf apply 完之後用 terraform state show 查出實際
# bucket/table 名稱寫入),backend 區塊本身不支援 var.*,fork 這份程式碼的人要重新
# 走一次任務 3.1/3.2 的 bootstrap 流程,產生屬於自己帳號的這份檔案。
terraform {
  backend "s3" {
    bucket         = "platform-tfstate-029099141993"
    key            = "platform/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "platform-tflock"
    encrypt        = true
  }
}
