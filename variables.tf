variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "project_name" {
  type    = string
  default = "platform"
}
variable "alert_email" {
  type = string
}
variable "backup_bucket_name" {
  type    = string
  default = ""
}
variable "rds_snapshot_retention_days" {
  type    = number
  default = 7
}
variable "rds_snapshot_schedule_expression" {
  type    = string
  default = "cron(30 14 * * ? *)"
}
