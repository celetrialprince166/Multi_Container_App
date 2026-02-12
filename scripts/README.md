# Deployment Scripts

This directory contains scripts for setting up and deploying the Notes application on AWS EC2.

## Scripts

### `setup-docker.sh`
**Purpose:** Initial Docker installation and environment setup.  
**When to run:** Once, when setting up a new EC2 instance.  
**Usage:** 
```bash
sudo ./scripts/setup-docker.sh
```

**What it does:**
- Installs Docker Engine
- Installs Docker Compose v2
- Configures Docker service to start on boot
- Adds ubuntu user to docker group
- Creates `/opt/notes-app` directory
- Installs additional utilities (git, curl, vim, etc.)

---

### `deploy.sh`
**Purpose:** Deploy/update the application on EC2.  
**When to run:** Every time you want to deploy new changes.  
**Usage:**
```bash
cd /opt/notes-app
./scripts/deploy.sh
```

**What it does:**
- Pulls latest code from Git
- Checks for `.env` file
- Stops old containers
- Builds and starts new containers
- Verifies deployment health

**Note:** This script is typically called automatically by GitHub Actions CI/CD pipeline.

---

## Workflow

### Initial Setup (One-time)
```bash
# 1. SSH to EC2 instance
ssh -i your-key.pem ubuntu@<EC2_IP>

# 2. Clone repository
git clone https://github.com/your-org/docker_lab.git /opt/notes-app
cd /opt/notes-app

# 3. Run Docker setup script
sudo ./scripts/setup-docker.sh

# 4. Log out and back in (for docker group to take effect)
exit
ssh -i your-key.pem ubuntu@<EC2_IP>

# 5. Create .env file (manually or via CI/CD)
cd /opt/notes-app
nano .env  # Add your secrets

# 6. Start application
docker compose up -d
```

### Subsequent Deployments
```bash
# Manual deployment
cd /opt/notes-app
./scripts/deploy.sh

# Or let GitHub Actions do it automatically!
```

---

## CI/CD Integration

These scripts are designed to work with GitHub Actions:

1. **`setup-docker.sh`** is embedded in Terraform user_data (runs on instance creation)
2. **`deploy.sh`** is called by the CD pipeline on every merge to main

See `.github/workflows/deploy.yml` for the full CI/CD configuration.

---

## Permissions

Make scripts executable:
```bash
chmod +x scripts/*.sh
```

---

## Security Notes

- Always use GitHub Secrets for sensitive data
- Never hardcode passwords or API keys in scripts
- Use environment variables from `.env` file
- Restrict SSH access to your IP only (security group)

---

## Troubleshooting

### Docker command not found
```bash
# Re-run setup script
sudo ./scripts/setup-docker.sh

# Or install manually
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### Permission denied when running docker
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in
```

### Containers not starting
```bash
# Check logs
docker compose logs

# Check if .env file exists
ls -la .env

# Verify environment variables
docker compose config
```

---

**For more details, see:** `TERRAFORM_CI_CD_PLAN.md`
