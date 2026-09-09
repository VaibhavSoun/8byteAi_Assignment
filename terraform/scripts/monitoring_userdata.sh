#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1
echo "=== Monitoring bootstrap started at $(date) ==="

dnf update -y
dnf install -y amazon-ssm-agent docker wget tar jq

systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl enable docker
systemctl start docker

# ─── Prometheus ───────────────────────────────────────────────────────────────
PROM_VER="2.49.1"
useradd --no-create-home --shell /bin/false prometheus || true
mkdir -p /etc/prometheus /var/lib/prometheus

wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROM_VER}.linux-amd64.tar.gz"
mv "prometheus-${PROM_VER}.linux-amd64/prometheus" /usr/local/bin/
mv "prometheus-${PROM_VER}.linux-amd64/promtool" /usr/local/bin/
mv "prometheus-${PROM_VER}.linux-amd64/consoles" /etc/prometheus/
mv "prometheus-${PROM_VER}.linux-amd64/console_libraries" /etc/prometheus/
rm -rf "prometheus-${PROM_VER}.linux-amd64"*
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Write prometheus config using shell heredoc (not Terraform template)
APP_IP="__APP_IP__"
PROJECT="__PROJECT__"

cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alerts.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter_app'
    static_configs:
      - targets: ['${APP_IP}:9100']

  - job_name: 'node_exporter_monitoring'
    static_configs:
      - targets: ['localhost:9100']
EOF

cat > /etc/prometheus/alerts.yml << 'EOF'
groups:
  - name: ec2_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.instance }}"

      - alert: HighDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 85
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High disk on {{ $labels.instance }}"
EOF

cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target
[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# ─── Node Exporter ────────────────────────────────────────────────────────────
NE_VER="1.7.0"
useradd --no-create-home --shell /bin/false node_exporter || true
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NE_VER}/node_exporter-${NE_VER}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NE_VER}.linux-amd64.tar.gz"
mv "node_exporter-${NE_VER}.linux-amd64/node_exporter" /usr/local/bin/
rm -rf "node_exporter-${NE_VER}.linux-amd64"*

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
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

# ─── Grafana ──────────────────────────────────────────────────────────────────
cat > /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

dnf install -y grafana

cat > /etc/grafana/grafana.ini << 'EOF'
[server]
http_port = 3000
root_url = %(protocol)s://%(domain)s/grafana/
serve_from_sub_path = true

[security]
admin_user = admin
disable_gravatar = true

[users]
allow_sign_up = false

[auth.anonymous]
enabled = false
EOF

mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
EOF

mkdir -p /var/lib/grafana/dashboards
mkdir -p /etc/grafana/provisioning/dashboards

cat > /etc/grafana/provisioning/dashboards/default.yml << 'EOF'
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: '8Byte DevOps'
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

chown -R grafana:grafana /var/lib/grafana /etc/grafana/provisioning

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

echo "=== Monitoring bootstrap completed at $(date) ==="
