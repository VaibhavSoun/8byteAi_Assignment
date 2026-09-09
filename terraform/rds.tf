# ─── RDS Subnet Group ────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "postgres" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Private subnets for RDS — no public access"
  subnet_ids  = aws_subnet.private[*].id

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

# ─── RDS Parameter Group ─────────────────────────────────────────────────────

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-pg-params"
  family      = "postgres15"
  description = "Custom parameter group for ${var.project_name}"

  # SecOps: enable query logging for audit
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  tags = { Name = "${var.project_name}-pg-params" }
}

# ─── RDS PostgreSQL Instance ──────────────────────────────────────────────────

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  # Engine
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = var.db_instance_class
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100 # Auto-scaling up to 100GB
  storage_type          = "gp3"
  storage_encrypted     = true # SecOps: encryption at rest

  # Credentials — pulled from random_password, NOT hardcoded
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  # Networking — SecOps: private only, no public access
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false # Cost optimization: single AZ for demo

  # Backup strategy
  backup_retention_period = 7       # 7-day automated backups
  backup_window           = "02:00-03:00" # UTC low-traffic window
  maintenance_window      = "sun:04:00-sun:05:00"
  delete_automated_backups = false

  # Monitoring
  monitoring_interval = 60 # Enhanced monitoring every 60s
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade"
  ]

  # Lifecycle
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"
  deletion_protection       = false # Set true in real production

  tags = { Name = "${var.project_name}-postgres" }

  depends_on = [aws_secretsmanager_secret_version.db_credentials]
}

# ─── RDS Enhanced Monitoring Role ────────────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─── CloudWatch Alarms for RDS ────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-high-cpu"
  alarm_description   = "RDS CPU utilization exceeded 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-rds-cpu-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-rds-high-connections"
  alarm_description   = "RDS connection count exceeded 80"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-rds-connections-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "rds_write_ops" {
  alarm_name          = "${var.project_name}-rds-high-write-ops"
  alarm_description   = "RDS write IOPS exceeded 1000"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "WriteIOPS"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-rds-write-ops-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "rds_free_memory" {
  alarm_name          = "${var.project_name}-rds-low-memory"
  alarm_description   = "RDS freeable memory dropped below 128MB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 134217728 # 128MB in bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-rds-memory-alarm" }
}
