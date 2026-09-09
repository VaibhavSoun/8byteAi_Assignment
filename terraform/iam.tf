# ─── App EC2 IAM Role ─────────────────────────────────────────────────────────
# Least privilege: SSM (Session Manager), ECR pull, Secrets Manager read only

resource "aws_iam_role" "app_ec2" {
  name        = "${var.project_name}-app-ec2-role"
  description = "Role for app EC2: SSM access, ECR pull, Secrets Manager read"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# SSM managed policy — enables Session Manager (no SSH needed)
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent — for sending logs + metrics
resource "aws_iam_role_policy_attachment" "app_cloudwatch" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Least privilege inline policy: ECR pull + Secrets Manager read only
resource "aws_iam_role_policy" "app_custom" {
  name = "${var.project_name}-app-custom-policy"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPullOnly"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerReadOnly"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Scoped to only this project's secrets
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app_ec2" {
  name = "${var.project_name}-app-instance-profile"
  role = aws_iam_role.app_ec2.name
}

# ─── Monitoring EC2 IAM Role ──────────────────────────────────────────────────
# SSM + CloudWatch read (Prometheus remote_write to CloudWatch optional)

resource "aws_iam_role" "monitoring_ec2" {
  name        = "${var.project_name}-monitoring-ec2-role"
  description = "Role for monitoring EC2: SSM + CloudWatch read"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.monitoring_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch_read" {
  role       = aws_iam_role.monitoring_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_instance_profile" "monitoring_ec2" {
  name = "${var.project_name}-monitoring-instance-profile"
  role = aws_iam_role.monitoring_ec2.name
}

# ─── GitHub Actions IAM User ──────────────────────────────────────────────────
# Least privilege: push to ECR + deploy (update launch template / instance refresh)

resource "aws_iam_user" "github_actions" {
  name = "${var.project_name}-github-actions"
  path = "/ci/"
  tags = { Purpose = "GitHub Actions CI/CD deployments" }
}

resource "aws_iam_user_policy" "github_actions" {
  name = "${var.project_name}-github-actions-policy"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPushOnly"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2DescribeForDeploy"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      }
    ]
  })
}
