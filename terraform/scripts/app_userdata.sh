#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1
echo "=== Bootstrap started at $(date) ==="

dnf update -y
dnf install -y docker amazon-ssm-agent aws-cli jq wget tar

systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# CloudWatch Agent
dnf install -y amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent

# Node Exporter
useradd --no-create-home --shell /bin/false node_exporter || true
NE_VER="1.7.0"
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NE_VER}/node_exporter-${NE_VER}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NE_VER}.linux-amd64.tar.gz"
mv "node_exporter-${NE_VER}.linux-amd64/node_exporter" /usr/local/bin/
rm -rf "node_exporter-${NE_VER}.linux-amd64"*

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Docker
systemctl enable docker
systemctl start docker

echo "=== Bootstrap completed at $(date) ==="
