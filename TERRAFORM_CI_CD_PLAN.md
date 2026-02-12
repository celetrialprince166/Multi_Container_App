# Terraform + CI/CD Migration Plan
## Notes App on AWS EC2 with Industry-Standard Secrets Management

---

## Executive Summary

This plan outlines the migration of the Docker Compose-based Notes application to AWS EC2 using Terraform for infrastructure-as-code, GitHub Actions for CI/CD, and AWS Secrets Manager for secure credential storage.

---

## Current Architecture (Baseline)

```
Client → Nginx (reverse proxy:80) → Frontend (Next.js:3000)
                                → Backend (NestJS:3001) → PostgreSQL (5432)
```

**Secrets & Config in Use:**
| Variable | Type | Used By |
|----------|------|---------|
| `DB_USERNAME` | Secret | Backend, Database |
| `DB_PASSWORD` | Secret | Backend, Database |
| `DB_NAME` | Config | Backend, Database |
| `DB_SSL` | Config | Backend |
| `NEXT_PUBLIC_API_URL` | Public (build-time) | Frontend |
| `PROXY_PORT` | Config | Proxy |

---

## Target Architecture (AWS)

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  AWS Cloud                                                       │
│  ┌──────────────────────┐                                        │
│  │  Security Group      │  Allow 80 (HTTP), 443 (HTTPS), 22 (SSH)│
│  └──────────┬───────────┘                                        │
│             │                                                     │
│  ┌──────────▼──────────────────────────────────────────────────┐│
│  │  EC2 Instance (Amazon Linux 2 / Ubuntu)                      ││
│  │  - Docker + Docker Compose                                   ││
│  │  - Same stack: Nginx → Frontend, Backend → PostgreSQL        ││
│  │  - EBS volume for PostgreSQL data                            ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                   │
│  ┌──────────────────────┐  (Optional: RDS later)                 │
│  │  Secrets Manager     │  DB_USERNAME, DB_PASSWORD, DB_NAME     │
│  └──────────────────────┘                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Project Structure & Secrets Strategy

### 1.1 Directory Layout (Recommended)

```
docker_lab/
├── .github/
│   └── workflows/
│       ├── ci.yml              # Test, lint, build on PR
│       └── deploy.yml          # Deploy to EC2 on merge to main
├── terraform/
│   ├── main.tf                 # Provider, backend
│   ├── variables.tf
│   ├── outputs.tf
│   ├── ec2.tf                  # EC2 instance
│   ├── security_groups.tf
│   ├── iam.tf                  # IAM for EC2, GitHub OIDC
│   ├── secrets.tf              # Secrets Manager (or Parameter Store)
│   └── user_data.tf            # Bootstrap script for EC2
├── scripts/
│   └── ec2-bootstrap.sh        # Install Docker, pull & run
├── backend/                    # (existing)
├── frontend/                   # (existing)
├── nginx/                      # (existing)
├── docker-compose.yml          # (existing, parameterized)
├── docker-compose.prod.yml     # Optional: production overrides
└── .env.example                # Template only, never real values
```

### 1.2 Secrets Management Strategy (Industry Standard)

| Principle | Implementation |
|-----------|----------------|
| **Never commit secrets** | `.env` in `.gitignore`; use `.env.example` with placeholders only |
| **Store in secret store** | AWS Secrets Manager (or SSM Parameter Store) for DB credentials |
| **Inject at runtime** | EC2 user-data or startup script fetches secrets before `docker-compose up` |
| **CI/CD auth without long-lived keys** | GitHub OIDC to assume IAM role; no `AWS_ACCESS_KEY_ID` in repo |
| **Least privilege** | IAM roles scoped to only what’s needed |

**Secrets Flow:**
1. Terraform creates secrets in AWS Secrets Manager (or you pre-create them manually).
2. EC2 instance role has `secretsmanager:GetSecretValue` for that secret.
3. Bootstrap script fetches secrets and writes `.env` (or passes env to Docker) at startup.
4. CI/CD uses OIDC to deploy; no static AWS credentials in GitHub.

---

## Phase 2: Terraform Implementation

### 2.1 Terraform Modules / Files

| File | Purpose |
|------|---------|
| `main.tf` | AWS provider, S3 backend (optional), locals |
| `variables.tf` | `aws_region`, `instance_type`, `key_name`, `environment` |
| `ec2.tf` | EC2 instance, AMI, instance profile |
| `security_groups.tf` | Inbound: 80, 443, 22; outbound: all |
| `iam.tf` | EC2 instance role, policies (Secrets Manager, ECR if used) |
| `secrets.tf` | Create secret in Secrets Manager (or data source if pre-created) |
| `outputs.tf` | `public_ip`, `public_dns` for access |

### 2.2 Key Terraform Resources

- **EC2**: `t3.small` or `t3.medium` (adjust for load)
- **AMI**: Latest Amazon Linux 2 or Ubuntu 22.04
- **Storage**: Root volume + optional EBS for `/var/lib/docker` or DB data
- **User Data**: Install Docker, Docker Compose, fetch secrets, clone/pull app, run `docker compose up -d`

### 2.3 Bootstrap Script Flow

```bash
# Pseudocode for ec2-bootstrap.sh
1. yum/apt update, install Docker + Docker Compose
2. aws secretsmanager get-secret-value --secret-id notes-app/db --query SecretString --output text > /opt/app/secrets.json
3. Parse JSON and export DB_USERNAME, DB_PASSWORD, DB_NAME
4. Clone repo (or receive via deploy pipeline)
5. Create .env from secrets
6. docker compose up -d
7. Enable docker to start on boot
```

---

## Phase 3: CI/CD Pipeline (GitHub Actions)

### 3.1 Pipeline Stages

| Stage | Trigger | Actions |
|-------|---------|---------|
| **CI** | PR to `main` | Lint, unit tests, build Docker images (no push) |
| **CD** | Push/merge to `main` | Build images, push to ECR (or build on EC2), SSH/deploy to EC2 |

### 3.2 Authentication: OIDC (No Long-Lived Secrets)

```
GitHub Actions → OIDC Provider (AWS) → Assume Role → Deploy
```

- No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in GitHub secrets
- Use `id-token: write` and `aws-actions/configure-aws-credentials@v4` with `role-to-assume`

### 3.3 GitHub Secrets (Only Non-Sensitive Identifiers)

| Secret | Purpose |
|--------|---------|
| `AWS_REGION` | Target region |
| (None for AWS creds) | OIDC handles auth |

### 3.4 CI Workflow Example

- Checkout code
- Setup Node.js
- Install deps, run lint + tests for backend and frontend
- Build Docker images (optional: fail if build fails)

### 3.5 CD Workflow Example

1. Checkout code
2. Configure AWS via OIDC
3. (Optional) Build and push images to ECR
4. SSH to EC2 (using SSM Session Manager or SSH key stored in Secrets Manager/Parameter Store)
5. Pull latest code/images, run `docker compose pull && docker compose up -d`
6. Or: use `aws ssm send-command` to trigger deploy script on EC2

---

## Phase 4: Implementation Order

### Step 1: Prepare Repository
- [ ] Initialize git (if not already)
- [ ] Add `.env` to `.gitignore`
- [ ] Create `.env.example` with placeholders (no real values)
- [ ] Ensure `NEXT_PUBLIC_API_URL` can be set at build time for frontend

### Step 2: Create AWS Secrets
- [ ] Manually create secret in AWS Secrets Manager: `notes-app/db` with keys `username`, `password`, `database`
- [ ] Or: Terraform creates it (you provide initial values via TF variables, not in code)

### Step 3: Terraform
- [ ] Create `terraform/` directory structure
- [ ] Define VPC (default or custom)
- [ ] Security group for EC2
- [ ] IAM role for EC2 (Secrets Manager access)
- [ ] EC2 instance with user_data
- [ ] Bootstrap script
- [ ] Output public IP/DNS

### Step 4: Docker Compose for Production
- [ ] Ensure `docker-compose.yml` reads from env file
- [ ] Create `scripts/ec2-bootstrap.sh` that fetches secrets and runs compose
- [ ] Test locally with `.env` (not committed)

### Step 5: CI Pipeline
- [ ] `.github/workflows/ci.yml`
- [ ] Lint + test backend and frontend
- [ ] Optionally build Docker images

### Step 6: OIDC & IAM
- [ ] Create GitHub OIDC provider in AWS (or use Terraform)
- [ ] IAM role for GitHub Actions with trust policy for your repo
- [ ] Permissions: `ec2`, `ssm`, `secretsmanager` (minimal)

### Step 7: CD Pipeline
- [ ] `.github/workflows/deploy.yml`
- [ ] Deploy on merge to `main`
- [ ] Use SSM Run Command or SSH to trigger update on EC2

### Step 8: DNS & HTTPS (Optional)
- [ ] Route 53 for domain
- [ ] ACM certificate
- [ ] Nginx config for HTTPS termination

---

## Phase 5: Security Checklist

- [ ] No secrets in code, Terraform state, or GitHub
- [ ] EC2 security group: restrict SSH (22) to your IP or use SSM only
- [ ] Database not exposed to internet (only backend container)
- [ ] Use HTTPS in production (certificate via Let’s Encrypt or ACM)
- [ ] Regular security updates on EC2 (unattended-upgrades or similar)
- [ ] Terraform state in S3 with encryption and state locking (DynamoDB)

---

## Phase 6: Alternative Considerations

| Option | Pros | Cons |
|--------|------|------|
| **Single EC2** | Simple, low cost | Single point of failure |
| **RDS for PostgreSQL** | Managed DB, backups | Extra cost, more Terraform |
| **ECR for images** | Cleaner CD, versioned images | More setup |
| **ECS/Fargate** | Scalable, managed | More complex, higher cost |

---

## Next Steps

1. **Confirm**: Single EC2 with Docker Compose is acceptable for your scope.
2. **Choose**: GitHub or GitLab (this plan uses GitHub Actions).
3. **Implement**: Follow Phase 4 step-by-step.
4. **Document**: Add a `DEPLOY.md` for your team with runbooks.

---

*Document Version: 1.0*
