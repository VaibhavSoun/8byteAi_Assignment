#!/bin/bash
set -euo pipefail

# ─── Variables ───────────────────────────────────────────────────────────────
AWS_REGION="${aws_region}"
SECRET_NAME="${secret_name}"
ECR_IMAGE_URI="${ecr_image_uri}"
APP_PORT="${app_port}"
PROJECT_NAME="${project_name}"

# ─── Logging ─────────────────────────────────────────────────────────────────
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1
echo "=== Bootstrap started at $(date) ==="

# ─── System Update ────────────────────────────────────────────────────────────
dnf update -y
dnf install -y docker amazon-ssm-agent aws-cli jq

# ─── SSM Agent (enables Session Manager — no SSH needed) ─────────────────────
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# ─── CloudWatch Agent ────────────────────────────────────────────────────────
dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      },
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "totalcpu": true
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/app/8byte-devops/application",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/app/8byte-devops/user-data",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

systemctl enable amazon-cloudwatch-agent

# ─── Prometheus Node Exporter (scraped by monitoring EC2) ────────────────────
useradd --no-create-home --shell /bin/false node_exporter || true

NODE_EXPORTER_VERSION="1.7.0"
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-*.tar.gz
mv node_exporter-*/node_exporter /usr/local/bin/
rm -rf node_exporter-*

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --collector.filesystem \
  --collector.cpu \
  --collector.meminfo \
  --collector.diskstats \
  --collector.netdev
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# ─── Docker Setup ────────────────────────────────────────────────────────────
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# ─── Fetch DB credentials from Secrets Manager ───────────────────────────────
echo "Fetching DB credentials from Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

DATABASE_URL=$(echo "$SECRET_JSON" | jq -r '.url')

# ─── ECR Login & Pull ────────────────────────────────────────────────────────
echo "Logging into ECR..."
ECR_REGISTRY=$(echo "$ECR_IMAGE_URI" | cut -d'/' -f1)
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "Pulling image: $ECR_IMAGE_URI"
docker pull "$ECR_IMAGE_URI"

# ─── Create app log directory ────────────────────────────────────────────────
mkdir -p /var/log/app

# ─── Run Application ─────────────────────────────────────────────────────────
docker run -d \
  --name app \
  --restart unless-stopped \
  -p "${APP_PORT}:${APP_PORT}" \
  -e DATABASE_URL="$DATABASE_URL" \
  -e PORT="${APP_PORT}" \
  -e ENVIRONMENT="production" \
  -v /var/log/app:/app/logs \
  "$ECR_IMAGE_URI"

echo "=== Bootstrap completed at $(date) ==="
