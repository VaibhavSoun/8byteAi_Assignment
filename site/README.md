# 8Byte AI DevOps Assignment

> **End-to-end DevOps implementation** ...

**Author:** Vaibhav Singh Soun | **Role:** DevOps Engineer

📋 [View Challenges & Resolutions](CHALLENGES.md) | 🏗️ [Architecture](#architecture-overview) | 📊 [Monitoring](#part-3-monitoring--logging) | 🔒 [Security](#part-4-security-implementation-secops)
## Architecture Overview

```
Internet
    │
    ▼
Application Load Balancer (Public Subnets - 2 AZs)
    │
    ├──► App EC2 t2.micro (Private Subnet) ──► RDS PostgreSQL (Private Subnet)
    │         FastAPI + Docker via ECR
    │
    └──► Monitoring EC2 t2.micro (Private Subnet)
              Prometheus + Grafana (CloudWatch datasource for RDS)
```

### Tech Stack

| Layer | Technology | Reason |
|---|---|---|
| Cloud | AWS ap-northeast-1 (Tokyo) | Free tier eligible region |
| IaC | Terraform v1.15 | Industry standard, modular |
| Compute | EC2 t2.micro | Free tier, simple to reason about |
| Container Registry | Amazon ECR | AWS-native, no extra auth |
| Database | RDS PostgreSQL 15.19 db.t3.micro | Managed, encrypted |
| Load Balancer | Application Load Balancer | Single public ingress point |
| CI/CD | GitHub Actions | Native to repo, free |
| Monitoring (EC2) | Prometheus + Grafana | OSS observability stack |
| Monitoring (RDS) | CloudWatch + Grafana | Right tool for managed service metrics |
| Secret Management | AWS Secrets Manager | No secrets in code |
| EC2 Access | AWS SSM Session Manager | No SSH, no port 22 |
| Security Scanning | Trivy | Container vulnerability scanning in CI/CD |
| Alerting | CloudWatch Alarms + SNS | 7 alarms across EC2 + RDS |

---

## Part 1: Infrastructure Provisioning

All infrastructure provisioned using Terraform with remote state in S3 (Tokyo region).

### Resources Created
- VPC `10.0.0.0/16` with 2 public + 2 private subnets across 2 AZs
- Internet Gateway + NAT Gateway (private EC2 internet access)
- Application Load Balancer (public)
- EC2 App Server (`8byte-devops-app-server`) in private subnet
- EC2 Monitoring Server (`8byte-devops-monitoring-server`) in private subnet
- RDS PostgreSQL 15.19 (`db-8byte-devops`) in private subnet
- ECR repository (`8byte-devops-app`) with lifecycle policy
- Security Groups with least-privilege rules
- IAM Roles with SSM access (no SSH keys)
- AWS Secrets Manager (DB + Grafana credentials, auto-generated passwords)
- CloudWatch Alarms + SNS Topic for alerts
- S3 bucket for ALB access logs + VPC Flow Logs

### EC2 Instances Running in Tokyo
![EC2 Instances](docs/screenshots/Screenshot_2026-09-09_235607.png)

### App EC2 Security Groups (Least Privilege — Port 8000 from ALB only)
![App Security Groups](docs/screenshots/Screenshot_2026-09-09_235717.png)

### App EC2 CloudWatch Monitoring
![App Monitoring](docs/screenshots/Screenshot_2026-09-09_235809.png)

### Monitoring EC2 Security Groups (Port 3000 Grafana, 9090 Prometheus)
![Monitoring Security Groups](docs/screenshots/Screenshot_2026-09-09_235851.png)

### Monitoring EC2 CloudWatch Monitoring
![Monitoring EC2](docs/screenshots/Screenshot_2026-09-09_235914.png)

### RDS PostgreSQL — Available, Encrypted, Private
![RDS Security](docs/screenshots/Screenshot_2026-09-09_235958.png)
![RDS Summary](docs/screenshots/Screenshot_2026-09-10_000021.png)

### VPC Resource Map (4 Subnets, IGW, NAT, Route Tables)
![VPC](docs/screenshots/Screenshot_2026-09-10_000107.png)

### Application Load Balancer — Active, Internet-facing
![ALB](docs/screenshots/Screenshot_2026-09-10_000153.png)

### ALB Resource Map — Both Targets Healthy ✅
![ALB Resource Map](docs/screenshots/Screenshot_2026-09-10_003014.png)

### ECR Repository (AES-256 Encrypted)
![ECR Repo](docs/screenshots/Screenshot_2026-09-10_001646.png)

### ECR Image Pushed (64MB, tagged latest)
![ECR Image](docs/screenshots/Screenshot_2026-09-10_010242.png)

### AWS Secrets Manager — 2 Secrets (DB + Grafana)
![Secrets Manager](docs/screenshots/Screenshot_2026-09-10_001606.png)

### Terraform Apply Output
```
Apply complete! Resources: 13 added, 0 changed, 0 destroyed.

Outputs:
alb_dns_name            = "8byte-devops-alb-502806677.ap-northeast-1.elb.amazonaws.com"
app_instance_id         = "i-0d2c9f600bf43f7fb"
app_instance_private_ip = "10.0.10.69"
ecr_repository_url      = "436287745154.dkr.ecr.ap-northeast-1.amazonaws.com/8byte-devops-app"
grafana_url             = "http://8byte-devops-alb-502806677.ap-northeast-1.elb.amazonaws.com/grafana"
rds_identifier          = "db-8byte-devops"
vpc_id                  = "vpc-064d8efea60fcba82"
```

---

## Part 2: Application Deployment

FastAPI application containerized with Docker, pushed to ECR, deployed to EC2 via SSM (no SSH).

### App Live — FastAPI Swagger UI via ALB
![FastAPI Swagger](docs/screenshots/Screenshot_2026-09-10_002428.png)

### Health Endpoint — `{"status":"healthy"}`
![Health Check](docs/screenshots/Screenshot_2026-09-10_002452.png)

### Root Endpoint Response
![Root](docs/screenshots/Screenshot_2026-09-10_002513.png)

### Docker Container Running on EC2 (via SSM Session Manager)
![Docker Running](docs/screenshots/Screenshot_2026-09-10_002618.png)

---

## Part 2: CI/CD Pipeline (GitHub Actions)

Three workflows implementing the full deployment lifecycle:

### Workflow 1 — PR Checks (`pr-checks.yml`)
Triggers on every Pull Request to `main`:
- Unit tests (SQLite in-memory, no DB needed)
- Integration tests (PostgreSQL service container)
- Dependency vulnerability scan (Safety)
- Container vulnerability scan (Trivy)
- Slack notification on failure

### Workflow 2 — Build & Deploy to Staging (`staging-deploy.yml`)
Triggers automatically on merge to `main`:
- Build Docker image with git SHA label
- Push to ECR (staging-latest tag)
- Trivy scan of pushed image
- Deploy via SSM SendCommand (no SSH)
- Health check via ALB
- Slack notification on success/failure

### Workflow 3 — Deploy to Production (`production-deploy.yml`)
Manual trigger only (`workflow_dispatch`):
- Confirmation string required (`deploy-to-production`)
- GitHub Environment protection → **manual approval gate**
- CRITICAL-only Trivy scan (blocks on CRITICAL CVEs)
- Deploy via SSM
- Slack notification

### Build & Push to ECR — All Steps Green ✅
![Build Pipeline](docs/screenshots/Screenshot_2026-09-10_002911.png)

### Full Staging Pipeline — Succeeded ✅
![Staging Success](docs/screenshots/Screenshot_2026-09-10_010308.png)

### Production Pipeline — Manual Approval + Security Gate
![Production Pipeline](docs/screenshots/Screenshot_2026-09-10_011016.png)

### Production Trivy Security Gate — Blocking CRITICAL CVEs
![Trivy Security Gate](docs/screenshots/Screenshot_2026-09-10_011041.png)

> The production deployment was intentionally blocked by Trivy finding CRITICAL vulnerabilities in the base Debian image. This demonstrates the security gate working as designed — protecting production from vulnerable containers. In production, the fix would be to update the base image to a patched version.

### GitHub Actions Secrets Configured
All 7 secrets configured for CI/CD authentication and deployment.

---

## Part 3: Monitoring & Logging

### Dashboard 1 — EC2 Infrastructure (Prometheus + Grafana)

Node Exporter running on both EC2 instances, scraped by Prometheus every 15s. Grafana dashboard (ID: 1860) imported showing real-time metrics:

- **CPU:** 7.1%
- **RAM:** 76.1% used
- **Disk:** 19.4% used  
- **Network I/O:** Live traffic
- **Uptime:** Tracked

![Grafana EC2 Dashboard](docs/screenshots/Screenshot_2026-09-10_000711.png)

### Dashboard 2 — RDS Monitoring (CloudWatch + Grafana)

CloudWatch datasource configured in Grafana showing RDS metrics for `db-8byte-devops`:

- **CPU Utilization:** Peaked at 49.3% during provisioning, stable at ~0.01%
- **Database Connections:** Live count
- **Freeable Memory:** ~188 MiB
- **Free Storage Space:** 18.9 GiB

![Grafana RDS Dashboard](docs/screenshots/Screenshot_2026-09-10_001222.png)

### CloudWatch Alarms — 7 Alarms, All OK ✅

| Alarm | Threshold | Metric |
|---|---|---|
| EC2 High CPU | > 80% | CPUUtilization |
| EC2 High Memory | > 85% | mem_used_percent (CWAgent) |
| EC2 High Disk | > 85% | disk_used_percent (CWAgent) |
| RDS High CPU | > 80% | CPUUtilization |
| RDS Low Memory | < 128MB | FreeableMemory |
| RDS High Connections | > 80 | DatabaseConnections |
| RDS High WriteIOPS | > 1000 | WriteIOPS |

All alarms trigger SNS → email notification.

![CloudWatch Alarms](docs/screenshots/Screenshot_2026-09-09_001534.png)

---

## Part 4: Security Implementation (SecOps)

| Practice | Implementation |
|---|---|
| No SSH / Port 22 | AWS SSM Session Manager exclusively |
| Least Privilege IAM | Separate roles per service, scoped inline policies |
| Secret Management | AWS Secrets Manager with auto-generated 32-char passwords |
| Private Subnets | EC2 + RDS never internet-exposed |
| Encrypted Storage | RDS storage encrypted, EC2 EBS volumes encrypted |
| Container Scanning | Trivy in CI/CD — warns on staging, blocks on CRITICAL in prod |
| Access Logging | ALB logs → S3 (30-day retention), VPC Flow Logs → CloudWatch |
| State Security | S3 backend with encryption + versioning |
| No Public IPs | `map_public_ip_on_launch = false` on all subnets |

---

## Setup & Deployment Guide

### Prerequisites
- AWS CLI v2 configured with SSO
- Terraform >= 1.5.0
- Git

### Step 1 — Bootstrap Terraform State
```bash
# Create S3 bucket for remote state
aws s3api create-bucket \
  --bucket 8byte-devops-tfstate-<account-id> \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1

aws s3api put-bucket-versioning \
  --bucket 8byte-devops-tfstate-<account-id> \
  --versioning-configuration Status=Enabled
```

### Step 2 — Configure backend.tf
```hcl
backend "s3" {
  bucket  = "8byte-devops-tfstate-<account-id>"
  key     = "prod/terraform.tfstate"
  region  = "ap-northeast-1"
  encrypt = true
}
```

### Step 3 — Deploy Infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Step 4 — Deploy Application
```bash
# Connect via Session Manager (no SSH)
aws ssm start-session --target <instance-id> --region ap-northeast-1

# On EC2 — build and run container
docker build -t app .
docker tag app:latest <ecr-url>:latest
docker push <ecr-url>:latest
docker run -d --name app --restart unless-stopped -p 8000:8000 <ecr-url>:latest
```

### Step 5 — Access Services
```
App API:    http://<alb-dns>/
Docs:       http://<alb-dns>/docs
Health:     http://<alb-dns>/health
Grafana:    http://<alb-dns>/grafana
            Username: admin
            Password: from AWS Secrets Manager → 8byte-devops/grafana/credentials
```

### Step 6 — Destroy All Infrastructure
```bash
cd terraform
terraform destroy
```

---

## Cost Optimization

- t2.micro instances (free tier eligible)
- db.t3.micro RDS (cheapest PostgreSQL)
- Single AZ (no multi-AZ cost for demo)
- ECR lifecycle policy: keep only last 10 images
- S3 lifecycle policy: expire ALB logs after 30 days
- Single NAT Gateway (cost-effective for demo)
- Estimated monthly cost if kept running: ~$30-40/month

---

## Repository Structure

```
├── .github/workflows/
│   ├── pr-checks.yml          # Tests + security scan on PR
│   ├── staging-deploy.yml     # Auto-deploy to staging on merge to main
│   └── production-deploy.yml  # Manual production deployment with approval
├── app/
│   ├── main.py                # FastAPI application
│   ├── Dockerfile             # Multi-stage, non-root user
│   ├── requirements.txt
│   └── tests/
│       ├── unit/              # SQLite in-memory tests
│       └── integration/       # PostgreSQL service tests
├── terraform/
│   ├── backend.tf             # S3 remote state + providers
│   ├── variables.tf           # All configurable parameters with validation
│   ├── outputs.tf             # Key resource outputs
│   ├── vpc.tf                 # VPC, subnets, IGW, NAT, flow logs
│   ├── security_groups.tf     # Least-privilege SGs
│   ├── iam.tf                 # IAM roles (SSM, ECR, Secrets Manager)
│   ├── ec2.tf                 # App + monitoring instances + CW alarms
│   ├── rds.tf                 # PostgreSQL + parameter group + CW alarms
│   ├── alb.tf                 # ALB + target groups + S3 access logs
│   ├── ecr.tf                 # Container registry + lifecycle policy
│   ├── secrets.tf             # Secrets Manager secrets
│   ├── sns.tf                 # SNS topic + email subscription
│   └── scripts/
│       ├── app_userdata.sh        # EC2 bootstrap: Docker, SSM, Node Exporter
│       └── monitoring_userdata.sh # Prometheus + Grafana setup
├── docs/
│   └── screenshots/           # Deployment proof (24 screenshots)
└── README.md
```

---

## Author
**Vaibhav Singh Soun**
DevOps Engineer Assignment — 8Byte AI Pvt Ltd
