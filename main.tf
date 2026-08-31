# 頂層只呼叫 infra module。換雲時把這裡改成 module "infra" { source = "./modules/gcp-infra" }
module "infra" {
  source                           = "./modules/aws-infra"
  project_name                     = var.project_name
  alert_email                      = var.alert_email
  aws_region                       = var.aws_region
  backup_bucket_name               = var.backup_bucket_name
  rds_snapshot_retention_days      = var.rds_snapshot_retention_days
  rds_snapshot_schedule_expression = var.rds_snapshot_schedule_expression
}
