# ─── ALB Security Group ───────────────────────────────────────────────────────
# Only public-facing SG. Accepts HTTP/HTTPS from internet.

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: allow HTTP and HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow ALB to reach app EC2 only"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ─── App EC2 Security Group ───────────────────────────────────────────────────
# SecOps: NO port 22. Traffic only from ALB. Egress to RDS + ECR/SSM.

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "App EC2: accept traffic from ALB only, no SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Prometheus scrape from monitoring EC2"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  # Egress: HTTPS only (ECR pull, SSM, Secrets Manager — all AWS APIs)
  egress {
    description = "HTTPS to AWS services (ECR, SSM, Secrets Manager)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "PostgreSQL to RDS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# ─── Monitoring EC2 Security Group ────────────────────────────────────────────
# Grafana UI accessible via ALB. Prometheus internal only.

resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-monitoring-sg"
  description = "Monitoring EC2: Grafana via ALB, Prometheus internal"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Grafana UI from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Prometheus internal scrape"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    description = "HTTPS to AWS services and scrape targets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Prometheus scrape node_exporter on app EC2"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = { Name = "${var.project_name}-monitoring-sg" }
}

# ─── RDS Security Group ───────────────────────────────────────────────────────
# SecOps: Only app EC2 can connect. No internet access ever.

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS: PostgreSQL access from app EC2 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from app EC2 only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # No egress needed for RDS
  egress {
    description = "Deny all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  tags = { Name = "${var.project_name}-rds-sg" }
}
