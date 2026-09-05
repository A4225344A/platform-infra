# Task follow-up: switch ai-agent notification delivery from SES to SNS.
#
# SES 寄件如果用 Yahoo/Gmail 這類免費信箱地址當寄件人,會在任何有落實 DMARC
# 的收件端(Gmail、Yahoo 本身)被拒收——SES 不是這些網域授權的寄信伺服器,
# SPF/DKIM 無法對齊,DMARC 一律判定失敗。SNS 的通知信是從 Amazon 自己已授權
# 的網域寄出,從不冒充使用者自己的信箱地址,因此完全不觸發這個問題,也不需要
# 購買網域或設定 SPF/DKIM/DMARC。
#
# 取捨:SNS 只會送給「已訂閱這個 topic 且按過一次確認信」的固定名單,不能像
# SES 那樣依 service_catalog 動態指定任意收件人——實際收件人清單交給操作者
# 用 aws sns subscribe 手動維護,agent.py 只負責 publish 到單一 topic。

resource "aws_sns_topic" "ai_agent_alerts" {
  name = "${var.project_name}-ai-agent-alerts"
}

resource "aws_iam_user_policy" "ai_agent_sns" {
  name = "${var.project_name}-ai-agent-sns-publish"
  user = aws_iam_user.ai_agent_ses.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishAlertTopic"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.ai_agent_alerts.arn
      }
    ]
  })
}
