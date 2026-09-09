# ─── ECR Repository ───────────────────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"

  # SecOps: scan images on push automatically
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.project_name}-ecr" }
}

# Keep only last 10 images — cost optimization
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "ecr_repository_url" {
  description = "ECR repository URL — set this in GitHub Actions secrets"
  value       = aws_ecr_repository.app.repository_url
}
