#!/bin/bash
# =============================================================================
# Monitoring Server Bootstrap Script
# =============================================================================
# Purpose: Install Docker, clone the repo (which contains all monitoring
#          configs in monitoring/), substitute the app server IP, then start
#          the stack.
#
# Terraform injects:
#   ${app_server_private_ip}  — private IP of the app EC2
#   ${grafana_admin_password} — Grafana admin password (from tfvars/sensitive)
#   ${slack_webhook_url}      — Slack webhook for Alertmanager notifications
#   ${git_repo_url}           — GitHub repo URL (configs live in monitoring/)
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
# [1/4] System Update + Prerequisites
# =============================================================================
echo "[1/4] Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release wget unzip git

# =============================================================================
# [2/4] Install Docker + Docker Compose Plugin
# =============================================================================
echo "[2/4] Installing Docker..."
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
# [3/4] Clone Repo and Deploy Monitoring Configs
# =============================================================================
echo "[3/4] Cloning repo and setting up monitoring configs..."

MONITORING_DIR="/opt/monitoring"

# Clone the repository — the monitoring/ directory contains all config files:
#   monitoring/prometheus.yml
#   monitoring/alert_rules.yml
#   monitoring/alertmanager.yml
#   monitoring/docker-compose.monitoring.yml
#   monitoring/grafana/provisioning/datasources/prometheus.yml
#   monitoring/grafana/provisioning/dashboards/dashboard.yml
#   monitoring/grafana/dashboards/notes-app-dashboard.json
git clone ${git_repo_url} /tmp/repo

# Copy the monitoring/ directory to /opt/monitoring (the working directory)
cp -r /tmp/repo/monitoring/. "$MONITORING_DIR/"
rm -rf /tmp/repo

# ── Inject the app server private IP into prometheus.yml ─────────────────────
# prometheus.yml uses the placeholder APP_SERVER_PRIVATE_IP which must be
# replaced with the actual EC2 private IP at boot time — this is the ONLY
# runtime substitution needed. Everything else is static config.
sed -i "s/APP_SERVER_PRIVATE_IP/${app_server_private_ip}/g" \
    "$MONITORING_DIR/prometheus.yml"

# ── Inject the Slack webhook URL into alertmanager.yml ───────────────────────
# alertmanager.yml uses the placeholder SLACK_WEBHOOK_URL which must be
# replaced with the actual webhook URL at boot time.
if [ -n "${slack_webhook_url}" ]; then
  sed -i "s|SLACK_WEBHOOK_URL|${slack_webhook_url}|g" \
      "$MONITORING_DIR/alertmanager.yml"
  echo "Slack webhook URL injected into alertmanager.yml"
else
  echo "WARNING: No Slack webhook URL provided — Alertmanager will not send notifications"
fi

# ── Write the Grafana admin password into an env file ────────────────────────
# docker-compose.monitoring.yml reads GRAFANA_ADMIN_PASSWORD from the
# environment. We write it to a .env file in the working directory so
# docker compose picks it up automatically.
cat > "$MONITORING_DIR/.env" << ENVEOF
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}
ENVEOF
chmod 600 "$MONITORING_DIR/.env"  # Only root can read the password

# ── Fix Grafana provisioning directory permissions ───────────────────────────
# Bitnami Grafana runs as UID 1001 and copies sample.yaml files into the
# provisioning directories at startup. The directories created by git clone
# are owned by root, so we chown them to UID 1001 to prevent "Permission denied".
chown -R 1001:1001 "$MONITORING_DIR/grafana"
echo "Grafana directory ownership set to UID 1001"

# =============================================================================
# [4/4] Start the Monitoring Stack
# =============================================================================
echo "[4/4] Starting monitoring stack..."
cd "$MONITORING_DIR"
docker compose -f docker-compose.monitoring.yml up -d

# Wait for containers to initialise, then print status
sleep 20
docker compose -f docker-compose.monitoring.yml ps

# Install AWS CLI (for manual CloudWatch/GuardDuty queries from this server)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

apt-get autoremove -y
apt-get clean

hostnamectl set-hostname "notes-monitoring"

echo "=============================================="
echo "Monitoring Server Bootstrap Complete!"
echo "Time: $(date)"
echo ""
echo "Services:"
echo "  Prometheus:    http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "  Grafana:       http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "  Alertmanager:  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9093"
echo "  Login:      admin / (see grafana_admin_password in Terraform)"
echo ""
echo "Scraping app server at: ${app_server_private_ip}"
echo "Logs: /var/log/user-data.log"
echo "=============================================="
