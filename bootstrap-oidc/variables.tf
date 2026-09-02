variable "project_name" {
  type    = string
  default = "platform"
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

# 沒有預設值,刻意強制每個 fork 這份程式碼的人自己填——OIDC 信任關係如果沿用
# 別人的帳號/組織名當預設值,忘記改就等於幫錯的 GitHub 帳號開了 AssumeRole 的門。
variable "github_org" {
  type        = string
  description = "GitHub 帳號或組織名(OIDC trust 的 sub 條件用,例如 repo:<github_org>/<repo>:...)"
}

variable "infra_repo_name" {
  type    = string
  default = "platform-infra"
}

variable "app_repo_name" {
  type    = string
  default = "platform-app"
}

variable "ui_repo_name" {
  type    = string
  default = "platform-ui"
}

variable "cloudfront_ui_distribution_id" {
  type        = string
  default     = "E1VMEDDXP35S53"
  description = "CloudFront distribution ID for the EngOps UI deployment workflow."
}

variable "ui_bucket_name" {
  type        = string
  default     = ""
  description = "S3 bucket used by the EngOps UI deployment workflow. Defaults to <project>-engops-ui-<account-id>."
}
