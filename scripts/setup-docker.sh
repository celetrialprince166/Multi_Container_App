#!/bin/bash
# =============================================================================
# Docker Setup Script for Ubuntu 22.04 LTS
# =============================================================================
# This script installs Docker Engine and Docker Compose on a fresh Ubuntu EC2
# instance. It's typically run once during initial server setup.
#
# Usage: sudo ./setup-docker.sh
# =============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}==>${NC} $1\n"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install Docker
install_docker() {
    log_step "Installing Docker Engine"

    # Update package index
    log_info "Updating package index..."
    apt-get update -y

    # Install prerequisites
    log_info "Installing prerequisites..."
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up Docker repository
    log_info "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index again
    apt-get update -y

    # Install Docker Engine
    log_info "Installing Docker Engine..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Verify Docker installation
    log_info "Verifying Docker installation..."
    docker --version

    log_info "✓ Docker installed successfully!"
}

# Configure Docker
configure_docker() {
    log_step "Configuring Docker"

    # Start and enable Docker service
    log_info "Starting Docker service..."
    systemctl start docker
    systemctl enable docker

    # Add ubuntu user to docker group (so no sudo needed for docker commands)
    log_info "Adding ubuntu user to docker group..."
    if id "ubuntu" &>/dev/null; then
        usermod -aG docker ubuntu
        log_info "✓ User 'ubuntu' added to docker group"
        log_warn "User 'ubuntu' needs to log out and back in for group changes to take effect"
    else
        log_warn "User 'ubuntu' not found. Skipping group addition."
    fi

    # Verify Docker Compose
    log_info "Verifying Docker Compose..."
    docker compose version

    log_info "✓ Docker configured successfully!"
}

# Create application directory
create_app_directory() {
    log_step "Creating application directory"

    APP_DIR="/opt/notes-app"
    
    if [ ! -d "$APP_DIR" ]; then
        log_info "Creating directory: $APP_DIR"
        mkdir -p "$APP_DIR"
        
        # Set ownership to ubuntu user
        if id "ubuntu" &>/dev/null; then
            chown ubuntu:ubuntu "$APP_DIR"
            log_info "✓ Directory created and owned by ubuntu user"
        else
            log_warn "User 'ubuntu' not found. Directory owned by root."
        fi
    else
        log_info "Directory $APP_DIR already exists"
    fi
}

# Install additional tools
install_tools() {
    log_step "Installing additional tools"

    log_info "Installing git, curl, and other utilities..."
    apt-get install -y \
        git \
        curl \
        wget \
        vim \
        htop \
        unzip

    log_info "✓ Additional tools installed!"
}

# Main function
main() {
    log_step "Docker Setup Script for Ubuntu 22.04 LTS"
    
    # Check if running as root
    check_root

    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log_warn "Docker is already installed!"
        docker --version
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Exiting..."
            exit 0
        fi
    fi

    # Run installation steps
    install_docker
    configure_docker
    create_app_directory
    install_tools

    # Summary
    log_step "Installation Complete!"
    log_info "✓ Docker Engine: $(docker --version)"
    log_info "✓ Docker Compose: $(docker compose version)"
    log_info "✓ Application directory: /opt/notes-app"
    log_info ""
    log_warn "IMPORTANT: If you added a user to the docker group, they need to log out and back in."
    log_info ""
    log_info "Next steps:"
    log_info "  1. Clone your repository to /opt/notes-app"
    log_info "  2. Create .env file with your secrets"
    log_info "  3. Run: docker compose up -d"
}

# Run main function
main "$@"
