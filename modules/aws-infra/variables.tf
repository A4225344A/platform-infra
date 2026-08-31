variable "project_name" {
  type = string
}
variable "aws_region" {
  type = string
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}
variable "allowed_web_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "alert_email" {
  type = string
}
variable "backup_bucket_name" {
  description = "S3 bucket for W3 pg_dump backups. Empty uses a deterministic project/account/region name."
  type        = string
  default     = ""
}
variable "rds_snapshot_retention_days" {
  description = "How many days of task 10 manual RDS snapshots to retain."
  type        = number
  default     = 7
}
variable "rds_snapshot_schedule_expression" {
  description = "EventBridge schedule for RDS manual snapshots. Default is 22:30 Asia/Taipei."
  type        = string
  default     = "cron(30 14 * * ? *)"
}
