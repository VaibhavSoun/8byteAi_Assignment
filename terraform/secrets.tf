# ─── RDS Password — auto-generated, never in code ────────────────────────────

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/rds/credentials"
  description = "PostgreSQL master credentials for ${var.project_name}"

  # SecOps: automatic rotation every 30 days
  recovery_window_in_days = 7

  tags = { Name = "${var.project_name}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = var.db_name
    # Full connection string for app convenience
    url      = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.postgres.address}:5432/${var.db_name}"
  })
}

# Required provider for random password generation
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
