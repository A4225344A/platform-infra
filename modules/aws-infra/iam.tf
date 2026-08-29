data "aws_caller_identity" "current" {}

resource "aws_iam_role" "node" {
  name = "${var.project_name}-node-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_instance_profile" "node" {
  name = "${var.project_name}-node-profile"
  role = aws_iam_role.node.name
}

# W3:AI 層需要的權限。刻意用 inline policy 而非 managed policy,
# 範圍鎖在實際會用到的模型與參數路徑,不給整個 bedrock:*。
resource "aws_iam_role_policy" "node_ai" {
  name = "${var.project_name}-node-ai"
  role = aws_iam_role.node.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # W3 v6.1.2:模型選型從 claude-3-haiku 換成 Nova Micro(主要判讀)+
        # Haiku 4.5(fallback),兩個都是跨區推論設定檔,需要同時授權
        # inference-profile 本身與它可能路由到的底層 foundation-model(region
        # 放寬為萬用字元)。實測 ID 用 `aws bedrock list-inference-profiles`
        # 查證,不是照文件猜的值(Nova 是 apac. 前綴,Haiku 4.5 是 jp. 前綴,
        # 兩個模型家族的推論設定檔命名規則不一樣)。
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream",
          "bedrock:Converse", "bedrock:ConverseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-*",

          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/apac.amazon.nova-micro-*",
          "arn:aws:bedrock:*::foundation-model/amazon.nova-micro-*",

          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/jp.anthropic.claude-haiku-4-5-*",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-*"
        ]
      },
      {
        Sid      = "SesSendAlerts"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Sid      = "ReadPlatformParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/platform/*"
      }
    ]
  })
}
