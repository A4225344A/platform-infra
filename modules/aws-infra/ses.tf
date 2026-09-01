# Task 11 follow-up: dedicated SES sender credentials for ai-agent.
#
# K3s on EC2 does not provide IRSA. Giving the pod node-role credentials would
# broaden its AWS identity to every permission on platform-node-role. This
# scoped IAM user is intentionally narrower and is injected through
# platform-secrets only after the operator patches Kubernetes.

resource "aws_ses_email_identity" "alert_sender" {
  email = var.alert_email
}

resource "aws_iam_user" "ai_agent_ses" {
  name = "${var.project_name}-ai-agent-ses"
  path = "/service/"
}

resource "aws_iam_access_key" "ai_agent_ses" {
  user = aws_iam_user.ai_agent_ses.name
}

resource "aws_iam_user_policy" "ai_agent_ses" {
  name = "${var.project_name}-ai-agent-ses-send"
  user = aws_iam_user.ai_agent_ses.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendFromConfiguredAlertIdentity"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = aws_ses_email_identity.alert_sender.arn
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.alert_email
          }
        }
      }
    ]
  })
}
