# Multi-Container Notes Application — DevOps CI/CD on AWS

A production-ready full-stack Notes application deployed on AWS EC2 using Docker, Terraform, and GitHub Actions. This project demonstrates infrastructure-as-code practices, automated CI/CD pipelines, container orchestration, and secure secrets management without long-lived credentials.

---

## Table of Contents

- [Architecture](#architecture)
- [Motivation](#motivation)
- [Key Technologies](#key-technologies)
- [Architecture Diagram](#architecture-diagram)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Jenkins CI/CD Pipeline](#jenkins-cicd-pipeline)
- [Project Structure](#project-structure)
- [Learning Outcomes](#learning-outcomes)
- [Challenges & Solutions](#challenges--solutions)
- [Future Improvements](#future-improvements)
- [Contributing](#contributing)
- [License](#license)
- [Author](#author)

---

## Architecture

The application consists of four containers: Nginx (reverse proxy), Next.js (frontend), NestJS (backend API), and PostgreSQL (database). Traffic flows through Nginx on port 80, which routes requests to the frontend or backend. The backend connects to an isolated PostgreSQL instance. All application images are built in CI, pushed to Amazon ECR, and deployed to a single EC2 instance via SSH. Infrastructure is provisioned with Terraform, and GitHub Actions orchestrates the entire build, test, push, and deploy pipeline.

---

## Motivation

This project was built to master end-to-end DevOps practices for containerized applications. The goals were to:

- Implement a complete CI/CD pipeline that builds, tests, containerizes, pushes to a registry, and deploys to EC2
- Apply infrastructure-as-code with Terraform for reproducible, version-controlled cloud resources
- Use OIDC for AWS authentication in CI/CD, eliminating long-lived credentials
- Understand multi-container networking, security groups, and secrets management
- Demonstrate industry-standard deployment patterns suitable for portfolio and interview discussions

---

## Key Technologies

- **Docker & Docker Compose**: Containerization and local orchestration. Chosen for consistency between local development and production.
- **Nginx**: Reverse proxy for routing, rate limiting, and single-entry-point architecture.
- **NestJS**: Backend API with TypeORM for database operations. Provides structure and type safety.
- **Next.js**: Frontend framework with server-side rendering capabilities.
- **PostgreSQL**: Relational database. Runs in an isolated network; only the backend can connect.
- **Terraform**: Infrastructure-as-code for AWS. Provisions EC2, ECR, security groups, IAM roles, and TLS-generated SSH keys.
- **GitHub Actions**: CI/CD automation. Runs tests, builds images, pushes to ECR, and deploys via SSH.
- **Jenkins**: Self-hosted CI/CD server extending the pipeline with static analysis, security scanning, SonarCloud quality gates, Trivy image scanning, and Slack notifications.
- **Amazon ECR**: Container registry for application images. Integrated with IAM and avoids Docker Hub rate limits.
- **AWS EC2**: Compute host running Ubuntu 22.04 with Docker. Bootstraped via user data for Docker and SSM agent.

---

## Architecture Diagram

![Multi-Container Notes Application - AWS Architecture](images/arch.png)

---

## Prerequisites

- Docker 24.0+
- Docker Compose v2+
- Terraform 1.0+
- Node.js 20.x (for local development)
- AWS CLI v2 (for Terraform and manual operations)
- Git
- An AWS account with permissions for EC2, ECR, IAM, and VPC

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/celetrialprince166/Multi_Container_App.git
cd Multi_Container_App
```

### 2. Local development (Docker Compose)

```bash
cp .env.example .env
# Edit .env with your DB credentials
docker compose up -d
```

The application will be available at `http://localhost`.

### 3. Deploy infrastructure with Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars (region, environment, github_org, github_repo)
terraform init
terraform plan
terraform apply
```

### 4. Configure GitHub Secrets

After `terraform apply`, configure these repository secrets (Settings → Secrets and variables → Actions):

| Secret           | Source                                          |
|------------------|-------------------------------------------------|
| `DB_USERNAME`    | Your choice (e.g., `notesapp_admin`)            |
| `DB_PASSWORD`    | Strong password                                 |
| `DB_NAME`        | `notesdb`                                       |
| `AWS_REGION`     | `eu-west-1` (or your region)                    |
| `AWS_ROLE_ARN`   | `terraform output github_actions_role_arn`      |
| `EC2_HOST`       | `terraform output instance_public_ip`           |
| `SSH_PRIVATE_KEY`| `terraform output -raw ec2_private_key`         |

### 5. First deployment

Push to the `main` branch. GitHub Actions will build, push images to ECR, and deploy to EC2. Access the application at `http://<EC2_PUBLIC_IP>`.

---

## Usage

### Local development

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down
```

### Infrastructure

```bash
cd terraform

# Plan changes
terraform plan

# Apply changes
terraform apply

# Output application URL
terraform output application_url
```

### Manual deployment (SSH)

```bash
# Retrieve private key
terraform output -raw ec2_private_key > key.pem
chmod 600 key.pem

# Connect to EC2
ssh -i key.pem ubuntu@$(terraform output -raw instance_public_ip)

# On EC2: pull and restart
cd /opt/notes-app
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin <ECR_REGISTRY>
docker compose -f docker-compose.ecr.yml pull
docker compose -f docker-compose.ecr.yml up -d
```

---

## Jenkins CI/CD Pipeline

In addition to the GitHub Actions workflow, this project includes an industry-standard **Declarative Jenkins Pipeline** (`Jenkinsfile`) that extends the CI/CD process with static analysis, security scanning, image vulnerability scanning, SonarCloud code quality gates, and automated deployment to EC2.

### Pipeline Overview

![Jenkins Pipeline Flow Graph](images/jenkinsflowgraph.png)

| # | Stage | What it does | Branch |
|---|-------|-------------|--------|
| 1 | **Checkout** | Clones repo, captures short SHA, author, commit message | All |
| 2 | **Static Code Analysis** | `tsc --noEmit` (backend) + `next lint` (frontend) — parallel | All |
| 3 | **Dependency Security Audit** | `npm audit --audit-level=high` for both services — JSON report archived | All |
| 4 | **Unit Tests & Coverage** | Skipped until Jest is configured; placeholder stage in place | All |
| 5 | **SonarCloud Analysis** | `sonar-scanner` via `withSonarQubeEnv` — uploads to SonarCloud | All |
| 6 | **Docker Build** | Builds `notes-backend`, `notes-frontend`, `notes-proxy` images tagged with short SHA | All |
| 7 | **Image Vulnerability Scan** | Trivy scans all three images for CRITICAL CVEs; reports archived | All |
| 8 | **Push to ECR** | Authenticates with AWS and pushes all images to Amazon ECR | `main` only |
| 9 | **Deploy to EC2** | SCP `.env` + `docker-compose.ecr.yml` to EC2, SSH rolling restart | `main` only |
| 10 | **Smoke Test** | `curl` with 5 retries — passes on HTTP 200/301/302 | `main` only |
| Post | **Cleanup** | Removes local Docker images, cleans workspace | Always |

---

### Jenkins Setup

#### Required Plugins

Install via **Manage Jenkins → Plugins**:

| Plugin | Purpose |
|--------|---------|
| Pipeline (workflow-aggregator) | Core declarative pipeline support |
| Git | SCM checkout |
| Docker Pipeline | `docker build` / `docker push` steps |
| AWS Credentials | AWS key binding |
| SonarQube Scanner | `withSonarQubeEnv` + `waitForQualityGate` |
| SSH Agent | SSH key injection for EC2 deployment |
| Slack Notification | `slackSend` build notifications |
| Timestamper | Timestamps in console output |
| Workspace Cleanup | `cleanWs()` post-build |
| AnsiColor | Coloured console output |
| HTML Publisher | Coverage report publishing |

#### Required Credentials

Add via **Manage Jenkins → Credentials → Global**:

| Credential ID | Type | Value |
|---|---|---|
| `aws-access-key-id` | Secret Text | AWS Access Key ID |
| `aws-secret-access-key` | Secret Text | AWS Secret Access Key |
| `aws-region` | Secret Text | e.g. `eu-west-1` |
| `ecr-registry` | Secret Text | `<account>.dkr.ecr.<region>.amazonaws.com` |
| `ec2-host` | Secret Text | EC2 public IP or hostname |
| `ec2-ssh-key` | SSH Username with private key | Username: `ubuntu`, Key: OpenSSH PEM format |
| `db-username` | Secret Text | Postgres username |
| `dbpassword` | Secret Text | Postgres password |
| `db-name` | Secret Text | Postgres database name |
| `sonarcloud-token` | Secret Text | SonarCloud user token |
| `slack-token` | Secret Text | Slack Bot OAuth token |

> [!IMPORTANT]
> The SSH private key stored under `ec2-ssh-key` **must** be in OpenSSH format (beginning with `-----BEGIN OPENSSH PRIVATE KEY-----`). PuTTY `.ppk` format will cause a `Load key: invalid format` error.

#### SonarCloud Server Configuration

**Manage Jenkins → Configure System → SonarQube servers**:
- Name: `SonarCloud` *(must match `withSonarQubeEnv('SonarCloud')` in the Jenkinsfile)*
- URL: `https://sonarcloud.io`
- Token: select the `sonarcloud-token` credential

#### Creating the Pipeline Job

1. **New Item → Pipeline**
2. Pipeline → Definition: **Pipeline script from SCM**
3. SCM: Git → `https://github.com/celetrialprince166/Multi_Container_App.git`
4. Script Path: `Jenkinsfile`
5. Branch: `*/main`

---

### Successful Pipeline Run — Evidence

The pipeline completed all 10 stages successfully on build #15, triggered from commit `6246005` on the `main` branch.

**Key log excerpts:**

```
✅ SonarCloud Analysis — EXECUTION SUCCESS (31.4s)
✅ Docker Build — notes-backend, notes-frontend, notes-proxy built and tagged 6246005
✅ Push to ECR — Login Succeeded; all 3 images pushed (backend, frontend, proxy)
✅ Deploy to EC2 — docker compose up -d; all 4 containers healthy
✅ Smoke Test — Attempt 1 — HTTP 200 → Smoke test passed
✅ Cleanup — workspace and local images removed
Finished: SUCCESS
```

**Smoke Test Result:**

![Smoke Test — HTTP 200](images/smoketest.png)

**Containers running on EC2 after deployment:**

```
NAME             IMAGE                        STATUS
notes-backend    .../notes-backend:latest     Up 11 seconds (healthy)
notes-database   postgres:15-alpine           Up 17 seconds (healthy)
notes-frontend   .../notes-frontend:latest    Up 5 seconds (healthy)
notes-proxy      .../notes-proxy:latest       Up < 1 second (health: starting)
```

---

### How Jenkins Extends GitHub Actions

| Capability | GitHub Actions | Jenkins Pipeline |
|---|---|---|
| Checkout + Build | ✅ | ✅ |
| Docker Build + Push to ECR | ✅ | ✅ |
| SSH Deploy to EC2 | ✅ | ✅ |
| Static Code Analysis (TypeScript + ESLint) | ❌ | ✅ |
| Dependency Security Audit (`npm audit`) | ❌ | ✅ |
| SonarCloud Code Quality Gate | ❌ | ✅ |
| Image Vulnerability Scan (Trivy) | ❌ | ✅ |
| Smoke Test (HTTP health check) | ❌ | ✅ |
| Slack Notifications | ❌ | ✅ |
| Workspace Cleanup | ❌ | ✅ |

---

## Project Structure

```
Multi_Container_App/
├── .github/
│   └── workflows/
│       └── ci-cd.yml           # Build, test, push to ECR, deploy via SSH
├── backend/                    # NestJS API
│   ├── src/
│   ├── Dockerfile
│   └── package.json
├── frontend/                   # Next.js application
│   ├── app/
│   ├── Dockerfile
│   └── package.json
├── nginx/                      # Reverse proxy
│   ├── nginx.conf
│   └── Dockerfile
├── terraform/
│   ├── main.tf                 # Provider, data sources
│   ├── variables.tf            # Input variables
│   ├── ec2.tf                  # EC2 instance
│   ├── ecr.tf                  # ECR repositories
│   ├── iam.tf                  # IAM roles, OIDC provider
│   ├── key_pair.tf             # TLS-generated SSH key
│   ├── security_groups.tf      # Firewall rules
│   ├── outputs.tf              # Output values
│   └── user_data.sh            # EC2 bootstrap script
├── scripts/
│   ├── deploy.sh               # Deployment automation
│   └── setup-docker.sh         # Docker installation
├── docs/
│   ├── GITHUB_SECRETS_SETUP.md
│   ├── RUNBOOK.md
│   └── TERRAFORM_CI_CD_PLAN.md
├── Jenkinsfile                 # Jenkins declarative pipeline (10 stages)
├── docker-compose.yml          # Local development
├── docker-compose.ecr.yml      # Production (ECR images)
└── .env.example
```

---

## Learning Outcomes

- Implemented a full CI/CD pipeline: checkout, build, test, Docker build, push to ECR, and SSH deployment
- Configured Terraform to provision EC2, ECR, IAM roles, security groups, and TLS-generated key pairs
- Set up GitHub OIDC for AWS authentication, eliminating static credentials in CI
- Designed multi-container networking with isolated database access and health checks
- Managed secrets via GitHub Secrets and environment variables, avoiding commits of sensitive data
- Resolved Docker Hub rate limits by using ECR Public for base images (e.g., PostgreSQL)

---

## Challenges & Solutions

### Challenge 1: ECR Registry Not Passed to Deploy Job

**Problem**: The deploy job received an empty `ECR_REGISTRY` from the build job, causing `docker login` to fail and image pulls to target Docker Hub instead of ECR.

**Solution**: Derived the ECR registry in the deploy job using `aws sts get-caller-identity` and the region. The deploy job now configures AWS credentials, computes the registry URL, and uses it for `.env` and remote commands.

**Learning**: Job-to-job outputs for conditional steps can be unreliable; deriving values in the consuming job improves robustness.

---

### Challenge 2: Docker Hub Unauthorized Error

**Problem**: `docker compose pull` failed with `unauthorized: incorrect username or password` when pulling `postgres:15-alpine` from Docker Hub.

**Solution**: Switched to `public.ecr.aws/docker/library/postgres:15-alpine`, the same image hosted on AWS ECR Public. No authentication is required, and rate limits are avoided.

**Learning**: Docker Hub imposes anonymous pull limits; ECR Public offers a compatible alternative for common base images.

---

### Challenge 3: OIDC Authentication Failure

**Problem**: `configure-aws-credentials` failed with "Credentials could not be loaded" despite correct `AWS_ROLE_ARN` and trust policy.

**Solution**: Added `id-token: write` and `contents: read` to the workflow `permissions` block. OIDC requires the `id-token` permission for the job to request a JWT from GitHub.

**Learning**: GitHub Actions OIDC depends on explicit permissions; the workflow must declare `id-token: write` for AWS federation to work.

---

### Challenge 4: SSH Key Management

**Problem**: Manually creating and distributing EC2 key pairs for CI/CD introduced friction and risk of key loss.

**Solution**: Used the Terraform TLS provider to generate an RSA 4096-bit key and register it with `aws_key_pair`. The private key is output as sensitive and added to GitHub Secrets once. No manual key creation is needed.

**Learning**: TLS provider enables reproducible, version-controlled key generation within Terraform.

---

### Challenge 5: Jenkins SSH Key — "Load key: invalid format" (Jenkins)

**Problem**: The `Deploy to EC2` stage failed immediately with `Load key: invalid format`. The `ec2-ssh-key` credential had been pasted in PuTTY `.ppk` format, which OpenSSH does not accept.

**Solution**: Regenerated the key in OpenSSH format (`ssh-keygen -t rsa -b 4096 -m PEM`) and replaced the Jenkins credential with the correctly formatted key beginning with `-----BEGIN OPENSSH PRIVATE KEY-----`.

**Learning**: Jenkins SSH credentials must be in OpenSSH PEM format. Always verify the key header before storing it in Jenkins; PuTTY keys are silently rejected at runtime, not at credential-save time.

---

### Challenge 6: Workspace Path with Spaces Breaking SCP/SSH (Jenkins)

**Problem**: The Jenkins agent workspace was named `jenkins lab` (with a space). The `SSH_KEY` variable was interpolated unquoted into `scp` and `ssh` commands, causing the shell to split the path and produce `Identity file not found` errors.

**Solution**: Wrapped `${SSH_KEY}` in double quotes in every `scp -i` and `ssh -i` invocation:
```bash
scp -o StrictHostKeyChecking=no -i "${SSH_KEY}" ...
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" ...
```

**Learning**: Always quote shell variables that may contain spaces, especially file paths derived from Jenkins workspace locations.

---

### Challenge 7: Deployment Stages Silently Skipped — Branch Detection (Jenkins)

**Problem**: The `Push to ECR`, `Deploy to EC2`, and `Smoke Test` stages were skipped on every build even when running on `main`. The pipeline used `when { branch 'main' }`, which only works in Multibranch Pipeline jobs. In a standard Pipeline job, `env.BRANCH_NAME` is `null`.

**Solution**: Extended the `when` condition to cover all ways Jenkins exposes the branch name:
```groovy
when {
    anyOf {
        branch 'main'
        expression { env.GIT_BRANCH == 'origin/main' }
        expression { env.GIT_BRANCH == 'refs/heads/main' }
    }
}
```
Added debug `echo` statements in the Checkout stage to print both `env.BRANCH_NAME` and `env.GIT_BRANCH`, which confirmed `env.GIT_BRANCH` was set to `origin/main`.

**Learning**: `branch 'main'` only works in Multibranch Pipeline jobs. Standard Pipeline jobs must use `env.GIT_BRANCH` for branch-conditional logic.

---

## Observability & Security

This project implements a comprehensive observability stack and security posture, ensuring production readiness.

### Architecture

- **App Server (EC2)**: Runs the application stack (Nginx, Frontend, Backend, Database) and Node Exporter (host metrics).
- **Monitoring Server (EC2)**: A dedicated instance running Prometheus, Grafana, and its own Node Exporter. It scrapes metrics from the App Server via private IP.

### Monitoring Stack

| Component | Port | Purpose |
|---|---|---|
| **Prometheus** | 9090 | Scrapes metrics from `/metrics` (backend) and `:9100` (Node Exporters). Stores time-series data. |
| **Grafana** | 3000 | Visualizes metrics with a pre-configured dashboard. Users log in via web UI. |
| **Node Exporter** | 9100 | Exposes OS-level metrics (CPU, RAM, Disk, Network) from both instances. |
| **CloudWatch Logs** | - | Captures container logs (stdout/stderr) for long-term retention and search. |

### Security Measures

- **Network Isolation**: The App Server only accepts HTTP/SSH traffic. Metrics ports (3001, 9100) are restricted to the Monitoring Server's security group.
- **IAM Least Privilege**:
  - App Server: Can only write logs to CloudWatch.
  - Monitoring Server: Can only read CloudWatch metrics (if configured).
- **Threat Detection**: GuardDuty monitors for malicious activity (e.g., unauthorized access, malware).
- **Audit Logging**: CloudTrail logs all API actions to an encrypted S3 bucket.

### Accessing the Dashboard

1. Get the Monitoring Server IP:
   ```bash
   terraform output monitoring_server_ip
   ```
2. Open `http://<MONITORING_IP>:3000` in your browser.
3. Login with `admin` and the password set in `terraform.tfvars`.
4. Navigate to **Dashboards -> Notes App Dashboard**.

---

## Future Improvements

- [ ] Add HTTPS with ACM and Route 53 for production domains
- [ ] Introduce RDS for PostgreSQL to separate database lifecycle from EC2
- [ ] Implement blue-green or canary deployments to reduce downtime
- [ ] Add Prometheus and Grafana for monitoring and alerting
- [ ] Restrict SSH (port 22) to specific IP ranges or use SSM Session Manager only
- [ ] Add Terraform remote state in S3 with DynamoDB locking
- [ ] Implement automated database backups and retention policies

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes (`git commit -m 'Add feature'`)
4. Push to the branch (`git push origin feature/your-feature`)
5. Open a Pull Request

For significant changes, open an issue first to discuss the approach.

---

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

## Author

**Prince** — DevOps Engineer in Training

- GitHub: [@celetrialprince166](https://github.com/celetrialprince166)
- Repository: [Multi_Container_App](https://github.com/celetrialprince166/Multi_Container_App)
