#!/bin/bash
# =============================================================================
# EC2 User Data Bootstrap Script
# =============================================================================
# Purpose: Install Docker, Docker Compose, and prepare environment
# Runs: ONCE on first instance boot
# =============================================================================

set -e  # Exit on error
set -x  # Print commands (for CloudWatch logs)

# =============================================================================
# Variables (from Terraform template)
# =============================================================================
APP_DIR="${app_directory}"
ENVIRONMENT="${environment}"
GIT_REPO="${git_repo_url}"

# =============================================================================
# Logging Setup
# =============================================================================
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=============================================="
echo "Starting EC2 Bootstrap"
echo "Environment: $ENVIRONMENT"
echo "App Directory: $APP_DIR"
echo "Time: $(date)"
echo "=============================================="

# =============================================================================
# System Update
# =============================================================================
echo "[1/7] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# =============================================================================
# Install Prerequisites
# =============================================================================
echo "[2/7] Installing prerequisites..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    wget \
    vim \
    htop \
    unzip

# =============================================================================
# Install Docker
# =============================================================================
echo "[3/7] Installing Docker..."

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update -y
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Verify Docker installation
docker --version
docker compose version

# =============================================================================
# Configure Docker
# =============================================================================
echo "[4/7] Configuring Docker..."

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Configure Docker daemon
# IMPORTANT: Do NOT set global log-opts here.
# Per-service logging blocks in docker-compose.ecr.yml use the awslogs driver.
# If daemon-level log-opts (max-size, max-file) are set globally, Docker bleeds
# them into per-service awslogs overrides — awslogs doesn't understand those opts
# and throws "unknown log opt 'awslogs-stream-prefix'" at container start.
# Each service manages its own logging options in the compose file.
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file"
}
EOF

# Restart Docker to apply config
systemctl restart docker

# =============================================================================
# Create Application Directory
# =============================================================================
echo "[5/7] Creating application directory..."

mkdir -p "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"
chmod 755 "$APP_DIR"

# Create a marker file
cat > "$APP_DIR/README.txt" <<EOF
Notes Application Directory
===========================
Created: $(date)
Environment: $ENVIRONMENT

This directory is managed by GitHub Actions CI/CD.
The application code will be deployed here automatically.

Manual Deployment:
1. Clone repository: git clone $GIT_REPO .
2. Create .env file with secrets
3. Run: docker compose up -d
EOF

chown ubuntu:ubuntu "$APP_DIR/README.txt"

# =============================================================================
# Install AWS CLI and SSM Agent
# =============================================================================
echo "[6/7] Installing AWS CLI and SSM Agent..."

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Verify AWS CLI
aws --version

# SSM Agent is pre-installed on Ubuntu AMIs, but ensure it's running
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent --no-pager

# =============================================================================
# Final Setup
# =============================================================================
echo "[7/7] Final setup..."

# Set hostname
hostnamectl set-hostname "notes-app-$ENVIRONMENT"

# Create deployment helper script
cat > /usr/local/bin/deploy-notes <<'EOF'
#!/bin/bash
# Quick deployment helper script
cd /opt/notes-app
git pull origin main 2>/dev/null || echo "Repository not cloned yet"
docker compose down
docker compose up -d --build
docker compose ps
EOF

chmod +x /usr/local/bin/deploy-notes

# Update system packages one final time
apt-get autoremove -y
apt-get clean

# =============================================================================
# Bootstrap Complete
# =============================================================================
echo "=============================================="
echo "Bootstrap completed successfully!"
echo "Time: $(date)"
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo "AWS CLI version: $(aws --version)"
echo "=============================================="
echo ""
echo "Next steps:"
echo "1. Deploy application via GitHub Actions CI/CD"
echo "2. Or manually: cd $APP_DIR && git clone <repo> ."
echo "3. Create .env file with secrets"
echo "4. Run: docker compose up -d"
echo ""
echo "Logs: /var/log/user-data.log"
echo "=============================================="
