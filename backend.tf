# 任務 3.2:此檔案要在 bootstrap 資源(見 bootstrap.tf)實際 apply 到 AWS 之後才能產生真正內容,
# 因為 bucket 名稱含真實的 AWS account ID,無法在沒有 API 存取的情況下算出來。
#
# 在有 AWS 認證的環境(如 AWS CloudShell)依序執行:
#
#   terraform init
#   terraform apply -var="alert_email=<你的email>"   # 只建 bootstrap.tf 的 S3 + DynamoDB
#
#   BUCKET=$(terraform state show aws_s3_bucket.tfstate | grep "bucket " | head -1 | awk '{print $3}' | tr -d '"')
#
#   cat > backend.tf << EOF
#   terraform {
#     backend "s3" {
#       bucket         = "$BUCKET"
#       key            = "platform/terraform.tfstate"
#       region         = "ap-northeast-1"
#       dynamodb_table = "${BUCKET%-tfstate-*}-tflock"
#       encrypt        = true
#     }
#   }
#   EOF
#
#   terraform init -migrate-state    # 輸入 yes,把本機 state 搬進 S3
#
# 完成後這個檔案會被上面產生的實際 backend 區塊覆蓋,此註解可以刪除。
