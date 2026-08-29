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
  description = "僅放行 control/worker 節點連線 PostgreSQL"
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
  publicly_accessible    = false
  multi_az               = false # 故意 Single-AZ:省下 standby replica 的雙倍運算費
  username               = "postgres"
  password               = data.aws_ssm_parameter.postgres_password.value
  skip_final_snapshot    = true
  apply_immediately      = true
}
