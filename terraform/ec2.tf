# ─── App EC2 Instance ────────────────────────────────────────────────────────

resource "aws_instance" "app" {
  ami                    = var.app_ami
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app_ec2.name

  # SecOps: no public IP, access only via Session Manager
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true # SecOps: encrypted root volume
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/scripts/app_userdata.sh", {
    aws_region     = var.aws_region
    secret_name    = aws_secretsmanager_secret.db_credentials.name
    ecr_image_uri  = var.ecr_image_uri
    app_port       = var.app_port
    project_name   = var.project_name
  }))

  tags = { Name = "${var.project_name}-app-server" }

  depends_on = [
    aws_nat_gateway.main,
    aws_db_instance.postgres,
    aws_secretsmanager_secret_version.db_credentials
  ]
}

# ─── Monitoring EC2 (Prometheus + Grafana) ────────────────────────────────────

resource "aws_instance" "monitoring" {
  ami                    = var.app_ami
  instance_type          = var.monitoring_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring_ec2.name

  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/scripts/monitoring_userdata.sh", {
    app_instance_ip  = aws_instance.app.private_ip
    aws_region       = var.aws_region
    project_name     = var.project_name
    grafana_password = random_password.grafana_admin.result
  }))

  tags = { Name = "${var.project_name}-monitoring-server" }

  depends_on = [aws_nat_gateway.main, aws_instance.app]
}

# ─── Grafana admin password in Secrets Manager ───────────────────────────────

resource "random_password" "grafana_admin" {
  length  = 24
  special = false # Grafana URL-safe
}

resource "aws_secretsmanager_secret" "grafana_credentials" {
  name                    = "${var.project_name}/grafana/credentials"
  description             = "Grafana admin credentials"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "grafana_credentials" {
  secret_id     = aws_secretsmanager_secret.grafana_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.grafana_admin.result
  })
}

# ─── CloudWatch Alarms for EC2 ───────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "${var.project_name}-ec2-high-cpu"
  alarm_description   = "App EC2 CPU exceeded 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = { InstanceId = aws_instance.app.id }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-ec2-cpu-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "ec2_memory" {
  alarm_name          = "${var.project_name}-ec2-high-memory"
  alarm_description   = "App EC2 memory utilization exceeded 85%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  # mem_used_percent is a custom metric from CloudWatch agent
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "notBreaching"

  dimensions = { InstanceId = aws_instance.app.id }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-ec2-memory-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "ec2_disk" {
  alarm_name          = "${var.project_name}-ec2-high-disk"
  alarm_description   = "App EC2 disk usage exceeded 85%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.app.id
    path       = "/"
    device     = "xvda1"
    fstype     = "xfs"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-ec2-disk-alarm" }
}
