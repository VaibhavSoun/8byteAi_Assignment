# ─── SNS Topic for All Alerts ────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name         = "${var.project_name}-alerts"
  display_name = "8Byte DevOps Alerts"

  tags = { Name = "${var.project_name}-alerts" }
}

# Email subscription — update with your email before apply
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "vaibhav@youremail.com" # Replace before terraform apply
}
