# W3:RDS PostgreSQL,取代自架 Postgres StatefulSet(見「階段三」文件任務 11.2)。
#
# 刻意跟 VPC/節點放在同一個 state,不像文件建議的獨立 platform-persistent:
# terraform-destroy.yml 的每日 destroy 只 -target 到 control/worker/EIP 三樣,
# 不會動到這裡,所以 RDS 不會被每日重建流程波及。但這也代表沒有自動停機,
# 要停用/啟用得自己另外排程 aws rds stop-db-instance/start-db-instance,
# 不能只靠這個 repo 現有的 workflow。

data "aws_ssm_parameter" "postgres_password" {
  name            = "/${var.project_name}/postgres-password"
  with_decryption = true
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-postgres"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow control/worker nodes to reach PostgreSQL"
  vpc_id      = aws_vpc.main.id
}
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each          = aws_subnet.public
  security_group_id = aws_security_group.rds.id
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value.cidr_block
}
resource "aws_vpc_security_group_egress_rule" "rds_out" {
  security_group_id = aws_security_group.rds.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# 緩解 pgvector CVE-2026-3172(平行 HNSW 索引建置路徑的緩衝區溢位)。
#
# 這台 RDS 目前的 engine minor version 還無法把 pgvector 升到已修補的 0.8.2
# (見「RDS任務3異常解決與驗證紀錄.md」異常 8),版本升不上去之前,
# 先用這個自訂 Parameter Group 把 max_parallel_maintenance_workers 關掉,
# 讓 CREATE INDEX/REINDEX 走單執行緒建置路徑,避開觸發該漏洞的平行掃描路徑。
# 副作用是大表建索引時間變長;本專案的 incidents 表量體小,影響可忽略。
#
# 這個參數本身是 dynamic(不需要重開機就能生效),但 RDS 把「換成不同的
# Parameter Group」這件事本身視為需要 reboot 才能完全同步 ——
# apply 完後用 aws rds describe-db-instances 確認 DBParameterGroups[].ParameterApplyStatus,
# 如果是 pending-reboot,需要另外手動 aws rds reboot-db-instance 一次
# (Single-AZ,沒有 standby 可以 failover,reboot 會有大約 1-2 分鐘的連線中斷)。
resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project_name}-postgres16"
  family = "postgres16"

  parameter {
    name         = "max_parallel_maintenance_workers"
    value        = "0"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project_name}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.small"
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true # 用預設 aws/rds 管理金鑰,未另建 CMK
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  multi_az               = false # 故意 Single-AZ:省下 standby replica 的雙倍運算費
  username               = "postgres"
  password               = data.aws_ssm_parameter.postgres_password.value
  skip_final_snapshot    = true
  apply_immediately      = true

  lifecycle {
    prevent_destroy = true
  }
}
