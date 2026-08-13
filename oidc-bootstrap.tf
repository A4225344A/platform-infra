# oidc-bootstrap.tf
# 這份檔案刻意獨立管理,不放進 modules/aws-infra/ 的主要 apply 流程——
# 原因是它定義的 IAM Role 本身就是 CI 拿來認證用的東西,
# 如果跟其他資源混在同一個 state 裡被 CI 自動 apply/destroy,
# 有機率不小心把 CI 自己正在用的認證路徑弄壞(自己拔自己的梯子)。
# 這份檔案只在 bootstrap 時手動 apply 一次,之後不動它。

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# 只給「唯讀 plan」用的角色:在 PR 開啟時觸發,只能 plan 不能 apply
resource "aws_iam_role" "gha_plan" {
  name = "${var.project_name}-gha-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:A4225344A/platform-infra:pull_request*" }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 給「真的會動資源」用的角色:只有 push 到 main、或手動 workflow_dispatch 才能用
resource "aws_iam_role" "gha_apply" {
  name = "${var.project_name}-gha-apply"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:A4225344A/platform-infra:ref:refs/heads/main" }
      }
    }]
  })
}
# 這裡用 PowerUserAccess 示範,正式使用建議收斂成
# 只涵蓋 VPC/EC2/ECR/IAM(有限)/Budgets/S3/DynamoDB 的自訂政策——
# 最小權限原則在這裡同樣適用,詳見文件末「已知取捨」。
resource "aws_iam_role_policy_attachment" "gha_apply_scoped" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

output "gha_plan_role_arn"  { value = aws_iam_role.gha_plan.arn }
output "gha_apply_role_arn" { value = aws_iam_role.gha_apply.arn }