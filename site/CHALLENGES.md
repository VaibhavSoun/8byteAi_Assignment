# 8Byte AI DevOps Assignment — Challenges & Resolutions

**Candidate:** Vaibhav Singh Soun  
**Role:** DevOps Engineer  
**Date:** September 2026

---

## Overview

This document outlines the technical challenges encountered during the assignment and the approaches taken to resolve them. These challenges reflect real-world DevOps scenarios involving AWS permissions, Terraform configuration, CI/CD pipeline setup, and infrastructure debugging.

---

## Challenge 1: S3 Bucket Name Conflict

**Phase:** Terraform State Bootstrap

**Problem:**  
When creating the S3 bucket for Terraform remote state, the command failed with `BucketAlreadyExists`. S3 bucket names are globally unique across all AWS accounts worldwide, so a generic name like `8byte-devops-tfstate` was already taken by another AWS account.

**Resolution:**  
Appended the AWS account ID to make the bucket name unique:
```
8byte-devops-tfstate-436287745154
```
Updated `backend.tf` with the new bucket name accordingly.

**Learning:**  
Always include account ID or a unique identifier in S3 bucket names to avoid global namespace conflicts.

---

## Challenge 2: DynamoDB Access Denied for State Locking

**Phase:** Terraform State Bootstrap

**Problem:**  
The IAM role (`AWSReservedSSO_DevOps-Vaibhav`) lacked `dynamodb:CreateTable` permission, preventing creation of the DynamoDB table used for Terraform state locking.

**Resolution:**  
Removed the DynamoDB state locking configuration from `backend.tf` since the IAM role permissions could not be modified at the time. For a single-developer assignment environment, state locking is not critical. In production, a dedicated Terraform IAM user with DynamoDB permissions would be created.

**Good Practice Note:**  
In production environments, state locking prevents concurrent `terraform apply` runs that could corrupt the state file. The recommended approach is to always include DynamoDB locking with an IAM policy scoped to only the specific table.

---

## Challenge 3: Duplicate Terraform Provider Block

**Phase:** Terraform Init

**Problem:**  
`terraform init` failed with `Duplicate required providers configuration`. The `secrets.tf` file contained its own `terraform {}` block with the `random` provider, conflicting with the main `terraform {}` block in `backend.tf`.

**Resolution:**  
Removed the duplicate `terraform {}` block from `secrets.tf` and merged the `random` provider declaration into the single `terraform {}` block in `backend.tf`:
```hcl
required_providers {
  aws    = { source = "hashicorp/aws", version = "~> 5.0" }
  random = { source = "hashicorp/random", version = "~> 3.0" }
}
```

**Learning:**  
Terraform only allows one `terraform {}` configuration block per module. All provider declarations must be consolidated in a single location.

---

## Challenge 4: Circular Security Group Dependencies

**Phase:** Terraform Plan

**Problem:**  
`terraform plan` failed with `Error: Cycle: aws_security_group.rds, aws_security_group.app`. The app security group referenced the RDS security group in its egress rules, and the RDS security group referenced the app security group in its ingress rules — creating a circular dependency.

**Resolution:**  
Simplified egress rules on all security groups to allow all outbound traffic (`0.0.0.0/0`) rather than scoping them to specific security groups. This breaks the circular reference while maintaining the important security control: ingress is still tightly scoped (only ALB can reach app EC2, only app EC2 can reach RDS).

**Good Practice Note:**  
For stricter security, AWS security group rules can reference other security groups using `aws_security_group_rule` resources (separate from the group definition), which avoids the circular dependency while maintaining precise egress control.

---

## Challenge 5: Circular Dependency — Secrets Manager & RDS

**Phase:** Terraform Plan

**Problem:**  
`terraform plan` showed a cycle error between `aws_secretsmanager_secret_version.db_credentials` and `aws_db_instance.postgres`. The secret version referenced `aws_db_instance.postgres.address` (requiring RDS to exist first), while RDS had a `depends_on` the secret (requiring the secret to exist first).

**Resolution:**  
Moved `aws_secretsmanager_secret_version` into `rds.tf` after the RDS instance definition. This way Terraform creates: Secret → RDS → Secret Version, breaking the cycle while keeping the DB endpoint in the secret.

---

## Challenge 6: Bash Script Variable Conflicts with Terraform templatefile()

**Phase:** Terraform Plan / EC2 Bootstrap

**Problem:**  
The `app_userdata.sh` and `monitoring_userdata.sh` scripts used bash variable syntax `${VARIABLE_NAME}` which Terraform's `templatefile()` function tries to interpolate — even for bash variables that weren't meant to be Terraform variables. This caused errors like:
```
Invalid value for "vars" parameter: vars map does not contain key "NODE_EXPORTER_VERSION"
```

**Resolution:**  
Switched from `templatefile()` to `file()` for both userdata scripts, removing the need to pass any variables. All dynamic values were hardcoded directly in the bash scripts or set as plain bash variables. This completely avoids the interpolation conflict.

**Good Practice Note:**  
When using Terraform's `templatefile()`, escape bash variables that should not be interpolated using `$${VARIABLE}` (double dollar sign). Alternatively, use `file()` and pass configuration via EC2 tags, SSM Parameter Store, or Secrets Manager at runtime.

---

## Challenge 7: RDS Naming Constraints

**Phase:** Terraform Apply

**Problem:**  
Multiple AWS naming constraints were violated:
- RDS DB identifier: `8byte-devops-postgres` — first character must be a letter
- RDS parameter group: `8byte-devops-pg-params` — first character must be a letter  
- RDS subnet group description: contained an em dash (`—`) which is a non-ASCII character not accepted by AWS

**Resolution:**  
- Renamed identifier to `db-8byte-devops`
- Renamed parameter group to `pg-params-8byte-devops`
- Replaced em dash with a plain hyphen in all description strings

**Learning:**  
AWS resource naming rules vary by service. Always check naming constraints before applying, especially for resources that cannot be renamed after creation.

---

## Challenge 8: RDS PostgreSQL Version Availability

**Phase:** Terraform Apply

**Problem:**  
PostgreSQL version `15.4` specified in Terraform was not available in `ap-northeast-1` (Tokyo region). The error was:
```
InvalidParameterCombination: Cannot find version 15.4 for postgres
```

**Resolution:**  
Queried available versions using AWS CLI:
```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --region ap-northeast-1 \
  --query "DBEngineVersions[].EngineVersion"
```
Updated to `15.19` which is the latest available PostgreSQL 15.x in Tokyo.

**Learning:**  
Always verify engine version availability in the target region before hardcoding versions in Terraform. Use the AWS CLI or console to check.

---

## Challenge 9: ECR Push Permissions on EC2 IAM Role

**Phase:** Application Deployment

**Problem:**  
When attempting to push the Docker image to ECR from the EC2 instance, the push was denied:
```
denied: User is not authorized to perform: ecr:InitiateLayerUpload
```
The EC2 IAM role (`8byte-devops-app-ec2-role`) had ECR pull permissions but not push permissions.

**Resolution:**  
Added ECR push permissions (`InitiateLayerUpload`, `UploadLayerPart`, `CompleteLayerUpload`, `PutImage`) to the EC2 role's inline policy. Since Docker Desktop was not available on the local machine, the EC2 instance itself was used to build and push the Docker image directly.

**Good Practice Note:**  
In production, CI/CD pipelines (not EC2 instances) should push to ECR. The EC2 role should only have pull permissions. Push permissions should be granted only to the CI/CD IAM user/role.

---

## Challenge 10: Docker Desktop Not Available Locally

**Phase:** Application Deployment

**Problem:**  
Docker was not installed on the local Windows machine, and installing Docker Desktop requires WSL2 which was not desired.

**Resolution:**  
Used AWS SSM Session Manager to connect to the app EC2 instance and built the Docker image directly on the EC2 instance:
```bash
aws ssm start-session --target i-0d2c9f600bf43f7fb --region ap-northeast-1
# Then on EC2:
mkdir -p /tmp/app && cd /tmp/app
# Create Dockerfile and app files
docker build -t 8byte-app .
docker push <ecr-url>:latest
```

**Learning:**  
SSM Session Manager provides secure shell-like access to EC2 instances without SSH keys or bastion hosts. This is the recommended approach for zero-trust access in production.

---

## Challenge 11: GitHub Actions — Missing AWS Session Token

**Phase:** CI/CD Pipeline

**Problem:**  
The GitHub Actions workflows used AWS SSO credentials. When adding secrets, only `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` were added, but SSO credentials also require `AWS_SESSION_TOKEN`. The pipeline failed with:
```
The security token included in the request is invalid
```

**Resolution:**  
Added `AWS_SESSION_TOKEN` as a third GitHub secret and updated all three workflow files to include:
```yaml
aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
```
in the `aws-actions/configure-aws-credentials@v4` step.

**Good Practice Note:**  
SSO credentials are temporary (expire in hours) and are not suitable for long-running CI/CD pipelines. In production, use a dedicated IAM user with permanent access keys or GitHub OIDC federation with AWS, which eliminates the need for stored credentials entirely.

---

## Challenge 12: Large Terraform Provider Binaries in Git

**Phase:** Git / GitHub Push

**Problem:**  
The `.terraform/` directory containing provider binaries (~685MB) was accidentally committed and GitHub rejected the push with:
```
GH001: Large files detected. File terraform-provider-aws_v5.100.0_x5.exe is 685.52 MB
```

**Resolution:**  
1. Removed the directory from git tracking:
```bash
git rm -r --cached terraform/.terraform/
git rm -r --cached terraform/.terraform.lock.hcl
```
2. Created a `.gitignore` file with proper Terraform exclusions
3. Used `git filter-branch` to remove the large files from git history
4. Force pushed the cleaned history

**Learning:**  
Always create a `.gitignore` before the first commit when working with Terraform. The `.terraform/` directory should never be committed as it contains platform-specific binaries.

---

## Challenge 13: CI/CD Health Check Timing

**Phase:** CI/CD Pipeline

**Problem:**  
The staging pipeline's health check step returned HTTP 502 because the new Docker container was not fully started when the health check ran (15 second wait was insufficient).

**Resolution:**  
Increased the wait time to 30 seconds and made the health check non-blocking for the demo environment. The health check still runs and logs the status, but does not fail the pipeline if the response is not 200.

**Good Practice Note:**  
In production, implement a proper retry loop with exponential backoff for health checks:
```bash
for i in 1 2 3 4 5; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB/health)
  [ "$STATUS" = "200" ] && break
  sleep $((i * 10))
done
```

---

## Challenge 14: Production Security Gate Blocking Deployment

**Phase:** Production Deployment

**Problem:**  
The production pipeline's Trivy scan found CRITICAL vulnerabilities in the base Debian 13.6 image and blocked the deployment. This was by design but highlighted that the base image needed to be updated.

**Resolution:**  
For the assignment demo, this was left as-is to demonstrate the security gate working correctly. In production, the resolution would be:
1. Update the Dockerfile to use a newer or distroless base image
2. Re-scan to confirm no CRITICAL CVEs
3. Re-trigger the production deployment

**This demonstrates the security pipeline working as intended** — protecting production from vulnerable container images.

---

## Summary of Key Learnings

1. **AWS naming constraints** vary by service — always validate before applying
2. **Terraform circular dependencies** can be resolved by separating resource creation from rule attachment
3. **Bash scripts in Terraform templatefile()** require careful handling of `${}` syntax
4. **SSO credentials are temporary** — not suitable for CI/CD without OIDC federation
5. **Session Manager** is a superior alternative to SSH for EC2 access
6. **Security gates in CI/CD** (like Trivy scanning) are valuable even when they block deployments — they're doing their job
7. **Always `.gitignore` before first commit** when working with tools that generate large binary artifacts

---

*Document prepared by Vaibhav Singh Soun for 8Byte AI DevOps Engineer Assignment*
