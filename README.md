# platform-infra

用 Terraform 管理的雲端基礎設施,搭配 GitHub Actions + OIDC 做全自動 CI/CD。核心設計是**供應商隔離**:所有 AWS 專屬的資源定義都收在單一 module 裡,上層只依賴一組與雲端供應商無關的通用輸出,換雲端時只需要重寫這個 module,其餘程式碼不動。

## 這套基礎設施建了什麼

- 雙可用區的 VPC(公有/私有子網路、IGW、路由表)
- 只開 80/443 的安全群組,不開 SSH(node 走 SSM 連線)
- ECR 容器映像倉庫(image tag 不可變、push 時自動掃描)
- EC2 節點用的 IAM Role(SSM 完整存取 + ECR 唯讀)
- 月度成本預算與三段式(33% / 66% / 100%)email 告警
- GitHub OIDC 信任關係,讓 GitHub Actions 用臨時憑證操作 AWS,不需要存放任何長期金鑰

## 架構

```
本機(編輯 .tf)
      │ git push
      ▼
GitHub repo(platform-infra)
      │ PR / push main / 手動觸發
      ▼
GitHub Actions Runner ──OIDC 換證──▶ AWS STS ──▶ IAM Role ──▶ AWS API
```

```
platform-infra/
├── main.tf, variables.tf, outputs.tf     # 頂層:組裝 module、轉發通用契約
├── backend.tf                            # S3 遠端狀態 + DynamoDB 鎖
├── bootstrap.tf                          # 一次性:建立 state bucket 與鎖表
├── bootstrap-oidc/                       # 獨立 state:GitHub OIDC 信任關係與三個 CI 角色
├── policy/portability.rego               # OPA 規則:擋掉硬編碼 registry 位址的 K8s manifest
├── .github/workflows/                    # terraform-plan / apply / destroy、部署到驗證機
└── modules/
    └── aws-infra/                        # 所有 AWS 專屬內容,換雲端只動這裡
        ├── network.tf                    # VPC、雙 AZ 子網路、IGW、路由
        ├── security.tf                   # 安全群組
        ├── registry.tf                   # ECR
        ├── iam.tf                        # 節點用 IAM Role / instance profile
        ├── budget.tf                     # 成本告警
        └── outputs.tf                    # 通用契約(見下)
```

### 通用契約

`modules/aws-infra/outputs.tf` 刻意用與供應商無關的名稱,而不是 `vpc_id`、`ecr_url` 這種 AWS 專屬名詞:

| 輸出 | 說明 |
|---|---|
| `network_id` | 承載工作負載的網路 ID |
| `public_subnet_ids` / `private_subnet_ids` | 子網路清單 |
| `node_security_group_id` | 節點使用的安全群組 |
| `registry_url` | 容器映像倉庫位址 |
| `node_instance_profile` | 節點的 IAM instance profile |

要換到其他雲端供應商時,新增一個 `modules/gcp-infra/`(或其他)、輸出同樣名稱的契約,頂層 `main.tf` 只需要改一行 `source`,其餘 workflow、變數、上層邏輯完全不動。

## GitHub Actions 三條 workflow

| Workflow | 觸發時機 | 用的角色 | 做的事 |
|---|---|---|---|
| `terraform-plan.yml` | 開 PR | `gha_plan`(唯讀) | `terraform plan`,結果留言到 PR |
| `terraform-apply.yml` | push main / 手動 | `gha_apply` | `terraform apply -auto-approve` |
| `terraform-destroy.yml` | 手動(可排程) | `gha_apply` | 銷毀指定資源,控制閒置成本 |
| `deploy-app.yml` | 收到跨 repo dispatch / 手動 | `gha_apply` | 透過 SSM 在驗證機上拉最新 image、重啟容器 |

三個角色的信任範圍互不重疊:`gha_plan` 只能讀、只在 PR 內觸發;`gha_apply` 只在 push main 或帶 `environment: production` 的 job 內可用;`gha_app_deploy`(定義在 `bootstrap-oidc/`)只准對單一 ECR repo 執行 push,不掛任何其他權限,專門給推送映像的應用程式 repo 使用。

## 事前準備

- AWS 帳號、可用的管理身分(建議透過 AWS CloudShell)
- Terraform ≥ 1.5
- 一個 GitHub 帳號或組織,以及 fork/建立出來的 repo

## 建置步驟

### 1. 建立遠端狀態後端

```bash
terraform init
terraform apply -target=aws_s3_bucket.tfstate -target=aws_dynamodb_table.tflock
```

把 apply 出來的 bucket 名稱、DynamoDB 表名填入 `backend.tf`(這個區塊是 Terraform 語法限制,不能用變數,必須是字面值),接著遷移到遠端後端:

```bash
terraform init -migrate-state
```

### 2. 建立 GitHub OIDC 信任關係

```bash
cd bootstrap-oidc
cat > terraform.tfvars << 'EOF'
github_org = "<你的 GitHub 帳號或組織名>"
EOF
terraform init
terraform apply
```

apply 完記下三個角色的 ARN:

```bash
terraform output gha_plan_role_arn
terraform output gha_apply_role_arn
terraform output gha_app_deploy_role_arn
```

### 3. 設定 GitHub Repository Variables

在 repo 的 **Settings → Secrets and variables → Actions → Variables** 新增:

| 名稱 | 值 |
|---|---|
| `AWS_REGION` | 例如 `ap-northeast-1` |
| `GHA_PLAN_ROLE_ARN` | 上一步的 `gha_plan_role_arn` |
| `GHA_APPLY_ROLE_ARN` | 上一步的 `gha_apply_role_arn` |
| `PROJECT_NAME` | 專案名稱(對應 `project_name` 變數) |
| `ALERT_EMAIL` | 接收成本告警的信箱 |
| `SERVICE_NAME` | 部署到驗證機的容器/服務名稱 |
| `GHCR_OWNER` | 存放應用程式映像的 GHCR 帳號(小寫) |

之後每次 push 到 main 都會自動 `apply`,開 PR 會自動 `plan` 並留言結果,不需要再手動登入操作雲端主控台。

## 搭配的應用程式 repo

這個 repo 只管基礎設施。容器化應用程式(建置映像、推送到 GHCR/ECR、觸發部署)放在獨立的應用程式 repo 裡,透過 `repository_dispatch` 事件呼叫本 repo 的 `deploy-app.yml`。兩邊各自的 CI/CD、權限、審查流程完全獨立,只透過「映像 tag」與「這裡建出來的 EC2/ECR」這兩個運作時介面銜接,對應真實團隊常見的基礎設施團隊 / 應用開發團隊分工。

## 成本

以 `ap-northeast-1` 估算:VPC、S3、DynamoDB、Budgets 幾乎零成本;ECR 依映像大小極小額計費;唯一持續產生費用的是驗證用 EC2(`t3.small`,約 $0.02/小時),預設已停用(`modules/aws-infra/verify.tf` 整段註解),需要時取消註解重新 apply 即可拉起,不用時可用 `terraform-destroy.yml` 手動銷毀。

## 已知取捨

- `bootstrap.tf`(建立 state bucket)與 `bootstrap-oidc/`(建立 OIDC 信任關係)只能在本機/CloudShell 用管理身分手動 apply 一次——這是刻意的,如果讓 CI 管理自己認證用的 IAM Role,存在「自己拔自己梯子」的風險。
- CI apply 角色目前掛 `PowerUserAccess` 示範,正式環境建議收斂成只涵蓋 VPC / EC2 / ECR / IAM(有限) / Budgets / S3 / DynamoDB 的自訂政策。
- `terraform.tfstate` 只存在 S3,遺失會導致 terraform 誤判資源不存在而嘗試重建,務必確保 S3 版本控制與存取權限正確設定。
