#!/bin/bash
# =============================================================================
# Monitoring Server Bootstrap Script
# =============================================================================
# Purpose: Install Docker, write all monitoring configs, start the stack.
# Runs: ONCE on first boot of the Observations Server EC2.
#
# Terraform injects these template variables:
#   ${app_server_private_ip}  — private IP of the app EC2 (for Prometheus targets)
#   ${grafana_admin_password} — Grafana admin password (from tfvars)
#   ${aws_region}             — AWS region (eu-west-1)
# =============================================================================

set -e
set -x

exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=============================================="
echo "Starting Monitoring Server Bootstrap"
echo "Time: $(date)"
echo "App Server IP: ${app_server_private_ip}"
echo "=============================================="

# =============================================================================
# [1/5] System Update + Prerequisites
# =============================================================================
echo "[1/5] Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release wget unzip

# =============================================================================
# [2/5] Install Docker + Docker Compose Plugin
# =============================================================================
echo "[2/5] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# =============================================================================
# [3/5] Write Monitoring Configuration Files
# =============================================================================
echo "[3/5] Writing monitoring configs..."

MONITORING_DIR="/opt/monitoring"
mkdir -p "$MONITORING_DIR/grafana/provisioning/datasources"
mkdir -p "$MONITORING_DIR/grafana/provisioning/dashboards"
mkdir -p "$MONITORING_DIR/grafana/dashboards"

# ── prometheus.yml ────────────────────────────────────────────────────────────
# Defines WHAT Prometheus scrapes and HOW OFTEN.
# The app server private IP is injected by Terraform templatefile().
cat > "$MONITORING_DIR/prometheus.yml" << 'PROMEOF'
# =============================================================================
# Prometheus Configuration
# =============================================================================
global:
  scrape_interval:     15s  # Pull metrics every 15 seconds
  evaluation_interval: 15s  # Evaluate alert rules every 15 seconds

# Load alert rules
rule_files:
  - /etc/prometheus/alert_rules.yml

scrape_configs:
  # ── NestJS Backend /metrics ─────────────────────────────────────────────────
  # Scrapes the custom http_requests_total and http_request_duration_seconds
  # metrics exposed by @willsoto/nestjs-prometheus, plus default Node.js metrics.
  - job_name: notes-backend
    static_configs:
      - targets: ['APP_SERVER_IP:3001']
    metrics_path: /metrics
    scrape_interval: 15s

  # ── Node Exporter on App Server ─────────────────────────────────────────────
  # OS-level metrics of the EC2 running the Notes app:
  # CPU, memory, disk I/O, network, filesystem usage.
  - job_name: node-exporter-app
    static_configs:
      - targets: ['APP_SERVER_IP:9100']
    scrape_interval: 15s

  # ── Node Exporter on Monitoring Server (self-monitoring) ────────────────────
  # Monitors the health of the Observations Server itself.
  - job_name: node-exporter-monitoring
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 15s

  # ── Prometheus self-scrape ───────────────────────────────────────────────────
  # Prometheus exposes its own metrics (scrape duration, target health, etc.)
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']
PROMEOF

# Replace placeholder with actual app server IP (injected by Terraform)
sed -i "s/APP_SERVER_IP/${app_server_private_ip}/g" "$MONITORING_DIR/prometheus.yml"

# ── alert_rules.yml ───────────────────────────────────────────────────────────
# Prometheus evaluates these rules every 15s.
# Firing alerts appear in the Prometheus /alerts UI and are forwarded to Grafana.
cat > "$MONITORING_DIR/alert_rules.yml" << 'ALERTEOF'
groups:
  - name: notes-app-alerts
    rules:

      # ── High HTTP Error Rate ─────────────────────────────────────────────────
      # Fires when >5% of requests in the last 5 minutes return 5xx status codes.
      # Formula: (5xx rate) / (total rate) > 0.05
      # "for: 1m" means it must stay above threshold for 1 minute before firing
      # (avoids false alarms from brief spikes).
      - alert: HighErrorRate
        expr: |
          (
            sum(rate(http_requests_total{status_code=~"5.."}[5m]))
            /
            sum(rate(http_requests_total[5m]))
          ) > 0.05
        for: 1m
        labels:
          severity: critical
          service: notes-backend
        annotations:
          summary: "High HTTP error rate on Notes API (>5%)"
          description: >
            Error rate is {{ $value | humanizePercentage }} over the last 5 minutes.
            Check backend logs: aws logs tail /notes-app/containers --filter-pattern ERROR

      # ── Backend Down ─────────────────────────────────────────────────────────
      # Fires when Prometheus cannot reach the backend /metrics endpoint.
      # "up == 0" means the last scrape failed (connection refused / timeout).
      - alert: BackendDown
        expr: up{job="notes-backend"} == 0
        for: 30s
        labels:
          severity: critical
          service: notes-backend
        annotations:
          summary: "Notes backend is unreachable"
          description: "Prometheus cannot scrape {{ $labels.instance }}. Check if the container is running."

      # ── High P95 Latency ─────────────────────────────────────────────────────
      # Fires when the 95th percentile request latency exceeds 2 seconds.
      - alert: HighLatency
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
          ) > 2
        for: 2m
        labels:
          severity: warning
          service: notes-backend
        annotations:
          summary: "High P95 latency on Notes API (>2s)"
          description: "P95 latency is {{ $value | humanizeDuration }}. Possible DB slowness or resource exhaustion."

      # ── App Server High CPU ───────────────────────────────────────────────────
      # Fires when app server CPU usage exceeds 80% for 5 minutes.
      - alert: HighCPU
        expr: |
          100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle",job="node-exporter-app"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
          service: app-server
        annotations:
          summary: "App server CPU usage >80%"
          description: "CPU usage is {{ $value | humanize }}% on {{ $labels.instance }}."
ALERTEOF

# ── Grafana datasource provisioning ───────────────────────────────────────────
# Grafana reads this file on startup and auto-creates the Prometheus datasource.
# No manual UI configuration needed.
cat > "$MONITORING_DIR/grafana/provisioning/datasources/prometheus.yml" << 'DSEOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090   # Docker service name — Grafana reaches Prometheus internally
    isDefault: true
    editable: false
DSEOF

# ── Grafana dashboard provider ────────────────────────────────────────────────
# Tells Grafana to load dashboards from the /etc/grafana/dashboards directory.
cat > "$MONITORING_DIR/grafana/provisioning/dashboards/dashboard.yml" << 'DBEOF'
apiVersion: 1
providers:
  - name: Notes App Dashboards
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
DBEOF

# ── docker-compose.monitoring.yml ─────────────────────────────────────────────
cat > "$MONITORING_DIR/docker-compose.monitoring.yml" << COMPOSEEOF
# =============================================================================
# Monitoring Stack — Observations Server
# =============================================================================
# Services: Prometheus, Grafana, Node Exporter
# All data persisted in named Docker volumes.
# =============================================================================

services:
  prometheus:
    image: public.ecr.aws/bitnami/prometheus:2.51.2
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      # Config file (written above by this script)
      - $MONITORING_DIR/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      # Alert rules
      - $MONITORING_DIR/alert_rules.yml:/etc/prometheus/alert_rules.yml:ro
      # Persistent storage for time-series data (survives restarts)
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'   # Keep 15 days of metrics
      - '--web.enable-lifecycle'               # Allow config reload via HTTP POST
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    networks:
      - monitoring

  grafana:
    image: public.ecr.aws/bitnami/grafana:10.4.2
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${grafana_admin_password}
      - GF_USERS_ALLOW_SIGN_UP=false          # Disable self-registration
      - GF_ANALYTICS_REPORTING_ENABLED=false  # No telemetry to Grafana Inc.
      - GF_INSTALL_PLUGINS=                   # No extra plugins needed
    volumes:
      # Persistent Grafana database (dashboards, users, settings)
      - grafana_data:/opt/bitnami/grafana/data
      # Auto-provision datasource (Prometheus)
      - $MONITORING_DIR/grafana/provisioning/datasources:/opt/bitnami/grafana/conf/provisioning/datasources:ro
      # Auto-provision dashboard loader
      - $MONITORING_DIR/grafana/provisioning/dashboards:/opt/bitnami/grafana/conf/provisioning/dashboards:ro
      # Dashboard JSON files
      - $MONITORING_DIR/grafana/dashboards:/etc/grafana/dashboards:ro
    depends_on:
      - prometheus
    networks:
      - monitoring

  node-exporter:
    image: public.ecr.aws/bitnami/node-exporter:1.8.2
    container_name: node-exporter-monitoring
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

networks:
  monitoring:
    name: monitoring-network

volumes:
  prometheus_data:
    name: prometheus-data
  grafana_data:
    name: grafana-data
COMPOSEEOF

# =============================================================================
# [4/5] Start the Monitoring Stack
# =============================================================================
echo "[4/5] Starting monitoring stack..."
cd "$MONITORING_DIR"
docker compose -f docker-compose.monitoring.yml up -d

# Wait for services to be healthy
sleep 15
docker compose -f docker-compose.monitoring.yml ps

# =============================================================================
# [5/5] Final Setup
# =============================================================================
echo "[5/5] Final setup..."
hostnamectl set-hostname "notes-monitoring"

# Install AWS CLI (for manual CloudWatch/GuardDuty queries from this server)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

apt-get autoremove -y
apt-get clean

echo "=============================================="
echo "Monitoring Server Bootstrap Complete!"
echo "Time: $(date)"
echo ""
echo "Services:"
echo "  Prometheus: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "  Grafana:    http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "  Login:      admin / ${grafana_admin_password}"
echo ""
echo "Scraping app server at: ${app_server_private_ip}"
echo "Logs: /var/log/user-data.log"
echo "=============================================="
