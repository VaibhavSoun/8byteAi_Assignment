terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket  = "8byte-devops-tfstate-436287745154"
    key     = "prod/terraform.tfstate"
    region  = "ap-northeast-1"
    encrypt = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "DevOps-Vaibhav-436287745154"

  default_tags {
    tags = {
      Project     = "8byte-devops"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "vaibhav-soun"
    }
  }
}