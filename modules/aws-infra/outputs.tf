# 通用契約:上層只看這些,不看 AWS 細節
output "network_id" {
  description = "承載工作負載的網路 ID(通用名,非 vpc_id)"
  value       = aws_vpc.main.id
}
output "public_subnet_ids" {
  description = "公有子網路(供節點使用)"
  value       = [for s in aws_subnet.public : s.id]
}
output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}
output "node_security_group_id" {
  value = aws_security_group.web.id
}
output "registry_url" {
  description = "容器映像倉庫位址(通用名,非 ecr_url;對應 v3 綁定點一)"
  value       = aws_ecr_repository.service.repository_url
}
output "node_instance_profile" {
  description = "節點的 IAM instance profile 名稱"
  value       = aws_iam_instance_profile.node.name
}
output "control_public_ip" { value = aws_eip.control.public_ip }
output "control_private_ip" { value = aws_instance.control.private_ip }
output "worker_asg_name" { value = aws_autoscaling_group.worker.name }
output "postgres_endpoint" { value = aws_db_instance.postgres.address }
output "backup_bucket_name" { value = aws_s3_bucket.db_backups.bucket }
output "rds_snapshot_backup_lambda_name" { value = aws_lambda_function.rds_snapshot_backup.function_name }
output "litellm_bedrock_access_key_id" {
  value = aws_iam_access_key.litellm_bedrock.id
}
output "litellm_bedrock_secret_access_key" {
  value     = aws_iam_access_key.litellm_bedrock.secret
  sensitive = true
}
output "ai_agent_ses_user_name" {
  value = aws_iam_user.ai_agent_ses.name
}
output "ai_agent_ses_identity_arn" {
  value = aws_ses_email_identity.alert_sender.arn
}
output "ai_agent_ses_access_key_id" {
  value = aws_iam_access_key.ai_agent_ses.id
}
output "ai_agent_ses_secret_access_key" {
  value     = aws_iam_access_key.ai_agent_ses.secret
  sensitive = true
}
