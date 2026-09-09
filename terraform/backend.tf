terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "8byte-devops-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "8byte-devops-tflock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "8byte-devops"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "vaibhav-soun"
    }
  }
}
