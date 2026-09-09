# ─── RDS Password — auto-generated, never in code ────────────────────────────

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/rds/credentials"
  description = "PostgreSQL master credentials for ${var.project_name}"

  recovery_window_in_days = 7

  tags = { Name = "${var.project_name}-db-secret" }
}

# Note: secret version is created after RDS in rds.tf
