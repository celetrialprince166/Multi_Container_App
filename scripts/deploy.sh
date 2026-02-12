#!/bin/bash
# =============================================================================
# Deployment Script for Notes Application
# =============================================================================
# This script is called by GitHub Actions CI/CD pipeline to deploy the app
# on the EC2 instance.
#
# Usage: ./deploy.sh
# =============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_DIR="/opt/notes-app"
COMPOSE_FILE="docker-compose.yml"

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

# Main deployment logic
main() {
    log_info "Starting deployment..."

    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then 
        log_warn "Not running as root. Some commands may require sudo."
    fi

    # Navigate to app directory
    if [ ! -d "$APP_DIR" ]; then
        log_error "App directory $APP_DIR does not exist!"
        exit 1
    fi
    cd "$APP_DIR"
    log_info "Changed to directory: $APP_DIR"

    # Pull latest code
    log_info "Pulling latest code from Git..."
    git fetch origin
    git pull origin main

    # Check if .env file exists
    if [ ! -f ".env" ]; then
        log_error ".env file not found! Deployment cannot continue."
        log_error "The CI/CD pipeline should have created this file."
        exit 1
    fi
    log_info ".env file found ✓"

    # Stop and remove old containers
    log_info "Stopping existing containers..."
    docker compose down || log_warn "No containers to stop"

    # Remove old images (optional - uncomment if you want to force rebuild)
    # log_info "Removing old images..."
    # docker compose down --rmi local

    # Build and start containers
    log_info "Building and starting containers..."
    docker compose up -d --build

    # Wait for containers to be healthy
    log_info "Waiting for containers to be healthy..."
    sleep 10

    # Check container status
    log_info "Checking container status..."
    docker compose ps

    # Check if all containers are running
    if docker compose ps | grep -q "unhealthy\|Exit"; then
        log_error "Some containers are not healthy!"
        log_error "Container logs:"
        docker compose logs --tail=50
        exit 1
    fi

    log_info "✓ Deployment completed successfully!"
    log_info "Application should be available at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'localhost')"
}

# Run main function
main "$@"
