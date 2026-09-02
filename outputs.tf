# 轉發 module 的通用契約給後續週次使用
output "network_id" { value = module.infra.network_id }
output "public_subnet_ids" { value = module.infra.public_subnet_ids }
output "private_subnet_ids" { value = module.infra.private_subnet_ids }
output "node_security_group_id" { value = module.infra.node_security_group_id }
output "registry_url" { value = module.infra.registry_url }
output "node_instance_profile" { value = module.infra.node_instance_profile }
output "control_public_ip" { value = module.infra.control_public_ip }
output "control_public_dns" { value = module.infra.control_public_dns }
output "control_private_ip" { value = module.infra.control_private_ip }
output "worker_asg_name" { value = module.infra.worker_asg_name }
output "postgres_endpoint" { value = module.infra.postgres_endpoint }
output "backup_bucket_name" { value = module.infra.backup_bucket_name }
output "rds_snapshot_backup_lambda_name" { value = module.infra.rds_snapshot_backup_lambda_name }
output "litellm_bedrock_access_key_id" {
  value = module.infra.litellm_bedrock_access_key_id
}
output "litellm_bedrock_secret_access_key" {
  value     = module.infra.litellm_bedrock_secret_access_key
  sensitive = true
}
output "ai_agent_ses_user_name" {
  value = module.infra.ai_agent_ses_user_name
}
output "ai_agent_ses_identity_arn" {
  value = module.infra.ai_agent_ses_identity_arn
}
output "ai_agent_ses_access_key_id" {
  value = module.infra.ai_agent_ses_access_key_id
}
output "ai_agent_ses_secret_access_key" {
  value     = module.infra.ai_agent_ses_secret_access_key
  sensitive = true
}
