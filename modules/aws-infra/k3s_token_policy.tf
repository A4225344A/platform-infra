resource "aws_iam_role_policy" "k3s_token" {
  name = "${var.project_name}-k3s-token"
  role = aws_iam_role.node.name # 沿用 W1 已建好的節點角色
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter",
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/k3s/*"
    }]
  })
}
