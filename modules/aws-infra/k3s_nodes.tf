# 節點互通 SG（k3s + Cilium 需要的埠）
resource "aws_security_group" "k3s" {
  name   = "${var.project_name}-k3s-sg"
  vpc_id = aws_vpc.main.id
}
resource "aws_vpc_security_group_ingress_rule" "api" {
  security_group_id            = aws_security_group.k3s.id
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.k3s.id
}
resource "aws_vpc_security_group_ingress_rule" "vxlan" {
  security_group_id            = aws_security_group.k3s.id
  from_port                    = 8472
  to_port                      = 8472
  ip_protocol                  = "udp" # Cilium VXLAN
  referenced_security_group_id = aws_security_group.k3s.id
}
resource "aws_vpc_security_group_ingress_rule" "health" {
  security_group_id            = aws_security_group.k3s.id
  from_port                    = 4240
  to_port                      = 4240
  ip_protocol                  = "tcp" # Cilium health
  referenced_security_group_id = aws_security_group.k3s.id
}
resource "aws_vpc_security_group_ingress_rule" "kubelet" {
  security_group_id            = aws_security_group.k3s.id
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.k3s.id
}
resource "aws_vpc_security_group_egress_rule" "out" {
  security_group_id = aws_security_group.k3s.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "control" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public["a"].id
  vpc_security_group_ids = [aws_security_group.k3s.id, aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name
  metadata_options {
    http_tokens = "required" # 強制 IMDSv2
    # W3:容器經 veth/bridge 會多一跳,hop=1 時 Pod 完全拿不到 IMDS 回應。
    # LiteLLM 需要 Bedrock 憑證、ai-agent 需要 SES 憑證,必須放行到 2。
    # 代價:同節點任何 Pod 都能取得節點角色權限——這是已知缺口,
    # 待 W4 的 NetworkPolicy 收斂,徹底解法是 IRSA / IAM Roles Anywhere。
    http_put_response_hop_limit = 2
  }
  tags = { Name = "${var.project_name}-control" }
  user_data = templatefile("${path.module}/user_data_control.sh", {
    AWS_REGION   = var.aws_region
    PROJECT_NAME = var.project_name
  })
}
resource "aws_instance" "worker" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.large" # W3:Presidio 的 spaCy en_core_web_lg 需 1–1.5GB 常駐,t3.small(2GB)放不下
  subnet_id              = aws_subnet.public["b"].id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  tags = { Name = "${var.project_name}-worker" }
  user_data = templatefile("${path.module}/user_data_worker.sh", {
    AWS_REGION         = var.aws_region
    PROJECT_NAME       = var.project_name
    CONTROL_PRIVATE_IP = aws_instance.control.private_ip # 建立隱含的建立順序依賴:worker 必須等 control 先建
  })
}
resource "aws_eip" "control" {
  instance = aws_instance.control.id
}
