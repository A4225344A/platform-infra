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
    http_tokens                 = "required" # 強制 IMDSv2
    http_put_response_hop_limit = 1          # 容器內的 Pod 多一跳,預設拿不到 IMDS 回應
  }
  tags = { Name = "${var.project_name}-control" }
}
resource "aws_instance" "worker" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public["b"].id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  tags = { Name = "${var.project_name}-worker" }
}
resource "aws_eip" "control" {
  instance = aws_instance.control.id
}
