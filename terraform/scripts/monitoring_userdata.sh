#!/bin/bash
set -euo pipefail

APP_INSTANCE_IP="${app_instance_ip}"
AWS_REGION="${aws_region}"
PROJECT_NAME="${project_name}"
GRAFANA_PASSWORD="${grafana_password}"

exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1
echo "=== Monitoring bootstrap started at $(date) ==="

# ─── System Update ────────────────────────────────────────────────────────────
dnf update -y
dnf install -y amazon-ssm-agent docker wget tar jq

systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

systemctl enable docker
systemctl start docker

# ─── Prometheus ───────────────────────────────────────────────────────────────
PROMETHEUS_VERSION="2.49.1"
useradd --no-create-home --shell /bin/false prometheus || true

mkdir -p /etc/prometheus /var/lib/prometheus

wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-*.tar.gz
mv prometheus-*/prometheus /usr/local/bin/
mv prometheus-*/promtool /usr/local/bin/
mv prometheus-*/consoles /etc/prometheus/
mv prometheus-*/console_libraries /etc/prometheus/
rm -rf prometheus-*

chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    project: '${PROJECT_NAME}'
    environment: 'production'

rule_files:
  - /etc/prometheus/alerts.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter_app'
    static_configs:
      - targets: ['${APP_INSTANCE_IP}:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'app-server'

  - job_name: 'node_exporter_monitoring'
    static_configs:
      - targets: ['localhost:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'monitoring-server'
EOF

# ─── Prometheus Alert Rules ───────────────────────────────────────────────────
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
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value }}% (threshold: 80%)"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value }}% (threshold: 85%)"

      - alert: HighDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 85
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High disk usage on {{ $labels.instance }}"
          description: "Disk usage is {{ $value }}% (threshold: 85%)"

      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} is down"
          description: "Node exporter is not reachable"
EOF

cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090 \
  --web.enable-lifecycle
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# ─── Node Exporter (for monitoring server itself) ─────────────────────────────
NODE_EXPORTER_VERSION="1.7.0"
useradd --no-create-home --shell /bin/false node_exporter || true

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
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=3

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

# Configure Grafana — run under /grafana subpath (served behind ALB)
cat > /etc/grafana/grafana.ini << EOF
[server]
domain = localhost
root_url = %(protocol)s://%(domain)s/grafana/
serve_from_sub_path = true
http_port = 3000

[security]
admin_user = admin
admin_password = ${GRAFANA_PASSWORD}
secret_key = $(openssl rand -hex 32)
disable_gravatar = true

[users]
allow_sign_up = false

[auth.anonymous]
enabled = false

[log]
mode = console file
level = info
EOF

# ─── Grafana Datasource provisioning (Dashboards as Code) ────────────────────
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

# ─── Grafana Dashboard provisioning ──────────────────────────────────────────
mkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards

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

# Dashboard 1: EC2 Infrastructure Overview
cat > /var/lib/grafana/dashboards/ec2_overview.json << 'DASHBOARD'
{
  "title": "EC2 Infrastructure Overview",
  "uid": "ec2-overview",
  "tags": ["ec2", "infrastructure"],
  "refresh": "30s",
  "panels": [
    {
      "id": 1,
      "title": "CPU Usage %",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "targets": [{
        "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)",
        "legendFormat": "{{instance}}"
      }],
      "fieldConfig": {
        "defaults": {
          "thresholds": {"steps": [{"color": "green", "value": 0}, {"color": "yellow", "value": 70}, {"color": "red", "value": 80}]},
          "unit": "percent", "max": 100
        }
      }
    },
    {
      "id": 2,
      "title": "Memory Usage %",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
      "targets": [{
        "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
        "legendFormat": "{{instance}}"
      }],
      "fieldConfig": {
        "defaults": {
          "thresholds": {"steps": [{"color": "green", "value": 0}, {"color": "yellow", "value": 75}, {"color": "red", "value": 85}]},
          "unit": "percent", "max": 100
        }
      }
    },
    {
      "id": 3,
      "title": "Disk Usage %",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "targets": [{
        "expr": "(1 - (node_filesystem_avail_bytes{mountpoint='/'} / node_filesystem_size_bytes{mountpoint='/'})) * 100",
        "legendFormat": "{{instance}}"
      }],
      "fieldConfig": {
        "defaults": {
          "thresholds": {"steps": [{"color": "green", "value": 0}, {"color": "yellow", "value": 75}, {"color": "red", "value": 85}]},
          "unit": "percent", "max": 100
        }
      }
    },
    {
      "id": 4,
      "title": "Network I/O",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "targets": [
        {"expr": "irate(node_network_receive_bytes_total{device='eth0'}[5m])", "legendFormat": "RX {{instance}}"},
        {"expr": "irate(node_network_transmit_bytes_total{device='eth0'}[5m])", "legendFormat": "TX {{instance}}"}
      ],
      "fieldConfig": {"defaults": {"unit": "bytes"}}
    }
  ]
}
DASHBOARD

# Dashboard 2: Application Health
cat > /var/lib/grafana/dashboards/app_health.json << 'DASHBOARD'
{
  "title": "Application Health",
  "uid": "app-health",
  "tags": ["app", "health"],
  "refresh": "15s",
  "panels": [
    {
      "id": 1,
      "title": "Instance Availability",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "targets": [{"expr": "up", "legendFormat": "{{instance}}"}],
      "fieldConfig": {
        "defaults": {
          "mappings": [{"options": {"0": {"text": "DOWN"}, "1": {"text": "UP"}}, "type": "value"}],
          "thresholds": {"steps": [{"color": "red", "value": 0}, {"color": "green", "value": 1}]}
        }
      }
    },
    {
      "id": 2,
      "title": "CPU Cores In Use",
      "type": "gauge",
      "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
      "targets": [{"expr": "count(node_cpu_seconds_total{mode='idle'}) by (instance) - (avg by(instance)(irate(node_cpu_seconds_total{mode='idle'}[5m])) * count(node_cpu_seconds_total{mode='idle'}) by (instance))"}],
      "fieldConfig": {"defaults": {"unit": "short", "min": 0, "max": 2}}
    },
    {
      "id": 3,
      "title": "Load Average (1m)",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
      "targets": [{"expr": "node_load1", "legendFormat": "1m {{instance}}"}, {"expr": "node_load5", "legendFormat": "5m {{instance}}"}],
      "fieldConfig": {"defaults": {"unit": "short"}}
    },
    {
      "id": 4,
      "title": "Open File Descriptors",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
      "targets": [{"expr": "node_filefd_allocated", "legendFormat": "{{instance}}"}],
      "fieldConfig": {"defaults": {"unit": "short"}}
    }
  ]
}
DASHBOARD

chown -R grafana:grafana /var/lib/grafana/dashboards /etc/grafana/provisioning

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

echo "=== Monitoring bootstrap completed at $(date) ==="
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000/grafana"
