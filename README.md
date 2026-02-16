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
- **Amazon ECR**: Container registry for application images. Integrated with IAM and avoids Docker Hub rate limits.
- **AWS EC2**: Compute host running Ubuntu 22.04 with Docker. Bootstraped via user data for Docker and SSM agent.

---

## Architecture Diagram

![Multi-Container Notes Application - AWS Architecture](images/image.png)

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
