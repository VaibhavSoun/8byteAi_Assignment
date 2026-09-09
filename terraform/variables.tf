# ─── General ────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "8byte-devops"
}

# ─── Networking ─────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (app + DB)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "AZs to deploy subnets into"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

# ─── Compute ─────────────────────────────────────────────────────────────────

variable "app_instance_type" {
  description = "EC2 instance type for application server"
  type        = string
  default     = "t2.micro"
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for Prometheus + Grafana server"
  type        = string
  default     = "t2.micro"
}

variable "app_ami" {
  description = "AMI ID for EC2 instances (Amazon Linux 2023)"
  type        = string
  default     = "ami-0599b6e53ca798bb2" # Amazon Linux 2023 ap-northeast-1
}

# ─── Database ────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for RDS (password stored in Secrets Manager)"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "Storage allocated for RDS in GB"
  type        = number
  default     = 20
}

# ─── App ─────────────────────────────────────────────────────────────────────

variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 8000
}

variable "ecr_image_uri" {
  description = "Full ECR image URI to deploy (set by CI/CD)"
  type        = string
  default     = ""
}
