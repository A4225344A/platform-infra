# 轉發 module 的通用契約給後續週次使用
output "network_id"             { value = module.infra.network_id }
output "public_subnet_ids"      { value = module.infra.public_subnet_ids }
output "private_subnet_ids"     { value = module.infra.private_subnet_ids }
output "node_security_group_id" { value = module.infra.node_security_group_id }
output "registry_url"           { value = module.infra.registry_url }
output "node_instance_profile"  { value = module.infra.node_instance_profile }
