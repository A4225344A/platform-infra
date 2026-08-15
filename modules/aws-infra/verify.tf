# modules/aws-infra/verify.tf
resource "aws_instance" "verify" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public["a"].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  # 開機自動裝好 Docker——AL2023 預設不含 Docker,沒有這段,
  # 不管是接下來手動 SSM 進去 docker run,還是任務 8 的自動部署,
  # 都會在第一個 docker 指令直接卡住(command not found)
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ssm-user
  EOF
  tags = { Name = "${var.project_name}-verify" }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
