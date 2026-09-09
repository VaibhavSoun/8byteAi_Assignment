#!/bin/bash
# Run this ONCE before first `terraform init`
# Creates the S3 bucket + DynamoDB table for remote state

set -euo pipefail

REGION="ap-northeast-1"
BUCKET_NAME="8byte-devops-tfstate"
DYNAMODB_TABLE="8byte-devops-tflock"

echo "=== Bootstrapping Terraform remote state ==="

# Create S3 bucket
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# Enable versioning (recover from accidental state corruption)
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Enable encryption at rest
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block all public access
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "✅ S3 bucket created: $BUCKET_NAME"

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo "✅ DynamoDB table created: $DYNAMODB_TABLE"
echo ""
echo "=== Now run: ==="
echo "  cd terraform"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
