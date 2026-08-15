# oidc-bootstrap.tf
# 這份檔案獨立在 bootstrap-oidc/ 這個子目錄,是自己的 root module、自己的 state
# (key = oidc/terraform.tfstate,見 provider.tf)——不是註解說說而已,CI 的
# terraform init/plan/apply 都在 repo 根目錄執行,物理上完全看不到這個子目錄,
# 也就完全碰不到這裡定義的 IAM Role,避免 CI 自己拔自己的梯子。
# 這份檔案只由人工在 CloudShell(admin 身分)手動 apply,之後不動它。

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# bootstrap.tf(根目錄的另一份 state)建的鎖表,這裡用 data source 讀它的 ARN
data "aws_dynamodb_table" "tflock" {
  name = "${var.project_name}-tflock"
}

data "aws_caller_identity" "current" {}

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
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:A4225344A*/platform-infra*:pull_request*" }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ⚠️ 只掛 ReadOnlyAccess 不夠——terraform plan 預設會先取得 state 鎖,
# 而寫入 DynamoDB 鎖表需要 PutItem/DeleteItem 這類寫入權限,ReadOnlyAccess 不含這些,
# plan 會卡在 "Acquiring state lock" 這步報 AccessDeniedException。
resource "aws_iam_role_policy" "gha_plan_state_lock" {
  name = "${var.project_name}-gha-plan-state-lock"
  role = aws_iam_role.gha_plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      Resource = data.aws_dynamodb_table.tflock.arn
    }]
  })
}

# 給「真的會動資源」用的角色:只有 push 到 main、手動 workflow_dispatch、或帶
# environment: production 的 job 才能用。
# sub 條件放兩種格式(StringLike 用陣列做 OR):
#   - "...:environment:production" → terraform-apply.yml / deploy-app.yml 這類設了
#     environment: production 的 job(走人工核准)
#   - "...:ref:refs/heads/main"    → terraform-destroy.yml 這種排程/無 environment 的
#     job(要無人值守跑,不能卡在等核准),否則 nightly destroy 排程永遠卡住等人點
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
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:A4225344A*/platform-infra*:environment:production",
            "repo:A4225344A*/platform-infra*:ref:refs/heads/main"
          ]
        }
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

# PowerUserAccess 刻意排除幾乎所有 iam:* 動作(含讀取),但 modules/aws-infra/iam.tf
# 的 platform-node-role/-profile 是無害的 EC2 節點角色,屬於 main state 正常管理範圍,
# 需要額外開一條精準的口子讓 gha_apply 能管它——Resource 明確鎖死在這兩個名字,
# 不含 gha_plan/gha_apply/OIDC provider 自己,CI 依然完全碰不到自己的認證鏈。
resource "aws_iam_role_policy" "gha_apply_node_iam" {
  name = "${var.project_name}-gha-apply-node-iam"
  role = aws_iam_role.gha_apply.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        # iam:Get*/iam:List* 涵蓋 GetRole、ListRolePolicies、ListAttachedRolePolicies、
        # ListInstanceProfilesForRole、ListRoleTags 等 provider refresh 會用到的各種讀取動作,
        # 一次開好避免之後每次 refresh 少一個權限就報一次 AccessDenied。
        "iam:Get*", "iam:List*",
        "iam:CreateRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        "iam:PassRole"
      ]
      Resource = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-node-role",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project_name}-node-profile"
      ]
    }]
  })
}

output "gha_plan_role_arn"  { value = aws_iam_role.gha_plan.arn }
output "gha_apply_role_arn" { value = aws_iam_role.gha_apply.arn }