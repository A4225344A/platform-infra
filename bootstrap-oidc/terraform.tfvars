# ⚠️ Fork 這份程式碼的人請先看這裡:下面這個值是原作者的 GitHub 帳號名,
# 只對這個 repo 的擁有者(A4225344A)有效——OIDC 信任關係綁定的是這個帳號,
# 用錯帳號名不會報錯,但會讓 GitHub Actions 永遠無法 AssumeRoleWithWebIdentity
# (因為 AWS 那邊信任的 sub 條件跟你實際的 repo owner 對不上)。
#
# 使用前務必改成你自己的 GitHub 帳號或組織名,例如:
#   github_org = "your-github-username"
github_org = "A4225344A"

# 以下三個有預設值(見 variables.tf),跟你的實際 repo 名稱/project_name/region
# 不同才需要在這裡覆蓋,同名可以整段刪掉不寫:
# infra_repo_name = "platform-infra"
# app_repo_name   = "platform-app"
# project_name    = "platform"
# aws_region      = "ap-northeast-1"
