# ─── Networking ──────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EC2 + RDS)"
  value       = aws_subnet.private[*].id
}

# ─── Load Balancer ────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "ALB public DNS — use this to access the app"
  value       = aws_lb.main.dns_name
}

output "app_url" {
  description = "Application URL"
  value       = "http://${aws_lb.main.dns_name}"
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${aws_lb.main.dns_name}/grafana"
}

# ─── Compute ──────────────────────────────────────────────────────────────────

output "app_instance_id" {
  description = "App EC2 instance ID (use with Session Manager)"
  value       = aws_instance.app.id
}

output "app_instance_private_ip" {
  description = "App EC2 private IP"
  value       = aws_instance.app.private_ip
}

output "monitoring_instance_id" {
  description = "Monitoring EC2 instance ID"
  value       = aws_instance.monitoring.id
}

# ─── Database ─────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
  sensitive   = true
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgres.identifier
}

# ─── Secrets ─────────────────────────────────────────────────────────────────

output "db_secret_arn" {
  description = "ARN of DB credentials secret in Secrets Manager"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "grafana_secret_arn" {
  description = "ARN of Grafana credentials in Secrets Manager"
  value       = aws_secretsmanager_secret.grafana_credentials.arn
}

# ─── Alerts ───────────────────────────────────────────────────────────────────

output "sns_topic_arn" {
  description = "SNS topic ARN for all alerts"
  value       = aws_sns_topic.alerts.arn
}
