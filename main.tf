# 頂層只呼叫 infra module。換雲時把這裡改成 module "infra" { source = "./modules/gcp-infra" }
module "infra" {
  source       = "./modules/aws-infra"
  project_name = var.project_name
  alert_email  = var.alert_email
  aws_region   = var.aws_region
}
