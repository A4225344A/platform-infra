# modules/aws-infra/verify.tf
#
# 停用中:手動 SSM 部署計時與自動部署計時的比較都跑完了,
# 不再需要這台常駐驗證機——整段用 block comment 停用,不刪除,保留給以後想再拉一台
# 同規格的驗證機時直接取消註解重用。停用後 terraform 完全看不到這個 resource,
# 效果等同刪除(下次 apply 不會因為 state 沒有它而嘗試重建),但程式碼還在 git 歷史與這個檔案裡。
#
# 重新啟用方式:把下面 /* 到 */ 整段刪掉(取消註解),git push,走一次 3.4 的
# plan → apply 流程即可重新建出來。


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

