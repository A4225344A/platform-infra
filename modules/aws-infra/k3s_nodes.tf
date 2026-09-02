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
resource "aws_vpc_security_group_ingress_rule" "otel" {
  security_group_id            = aws_security_group.k3s.id
  from_port                    = 4317
  to_port                      = 4318
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
  ami = data.aws_ami.al2023.id
  # W3:t3.medium(4GB)撐不住 k3s server + Cilium(agent/operator/envoy)+
  # 整套 kube-prometheus-stack(Prometheus/Grafana/Alertmanager/kube-state-metrics/
  # operator)同時跑,實測會在沒有 swap 的情況下觸發 kswapd0 抖動,load average
  # 衝到 20+、API server 連線逾時。升到 t3.large(8GB),vCPU 數不變,只加記憶體。
  instance_type          = "t3.large"
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
  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_launch_template" "worker" {
  name_prefix            = "${var.project_name}-worker-"
  image_id               = data.aws_ami.al2023.id
  instance_type          = "t3.large" # W3:Presidio 的 spaCy en_core_web_lg 需 1–1.5GB 常駐,t3.small(2GB)放不下
  vpc_security_group_ids = [aws_security_group.k3s.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-worker" }
  }

  user_data = base64encode(templatefile("${path.module}/user_data_worker.sh", {
    AWS_REGION         = var.aws_region
    PROJECT_NAME       = var.project_name
    CONTROL_PRIVATE_IP = aws_instance.control.private_ip # 建立隱含的建立順序依賴:worker 必須等 control 先建
  }))
  lifecycle {
    ignore_changes = [image_id]
  }
}

resource "aws_autoscaling_group" "worker" {
  name                = "${var.project_name}-worker"
  min_size            = 2
  desired_capacity    = 2
  max_size            = 4
  vpc_zone_identifier = [aws_subnet.public["a"].id, aws_subnet.public["b"].id]

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.project_name}"
    value               = "owned"
    propagate_at_launch = false
  }

  depends_on = [aws_instance.control]
}
resource "aws_eip" "control" {
  instance = aws_instance.control.id
}
