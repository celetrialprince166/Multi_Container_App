# GitHub Actions Workflows

This directory contains CI/CD workflows for automating testing and deployment of the Notes application.

## 📁 Workflows (To Be Created)

### `ci.yml` - Continuous Integration
**Trigger:** Pull Request to `main` branch  
**Purpose:** Run tests and checks before merging

**Steps:**
1. Checkout code
2. Setup Node.js
3. Install dependencies (backend + frontend)
4. Run linters
5. Run unit tests
6. Build Docker images (validation only, no push)
7. Report status

**Branch Protection:** Require CI to pass before merging

---

### `deploy.yml` - Continuous Deployment
**Trigger:** Push/merge to `main` branch  
**Purpose:** Deploy application to AWS EC2

**Steps:**
1. Checkout code
2. Configure AWS credentials (via OIDC)
3. Create `.env` file from GitHub Secrets
4. Connect to EC2 (via SSM or SSH)
5. Run deployment script
6. Verify containers are healthy
7. Send deployment notification

**Authentication:** Uses GitHub OIDC (no long-lived AWS keys)

---

## 🔐 Required GitHub Secrets

Configure these in: **Settings → Secrets and variables → Actions**

### AWS Configuration
| Secret | Example Value | Description |
|--------|---------------|-------------|
| `AWS_REGION` | `eu-west-1` | AWS region for deployment |
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789:role/GitHubActionsRole` | IAM role for OIDC |
| `EC2_INSTANCE_ID` | `i-0123456789abcdef` | EC2 instance ID (from Terraform output) |
| `EC2_HOST` | `54.123.45.67` | EC2 public IP (from Terraform output) |

### Application Secrets
| Secret | Example Value | Description |
|--------|---------------|-------------|
| `DB_USERNAME` | `notesapp_admin` | Database username |
| `DB_PASSWORD` | (strong password) | Database password (20+ chars) |
| `DB_NAME` | `notesdb` | Database name |

### Optional (for SSH deployment method)
| Secret | Example Value | Description |
|--------|---------------|-------------|
| `SSH_PRIVATE_KEY` | (private key content) | EC2 SSH key (if not using SSM) |

---

## 🚀 Workflow Flow

```
┌─────────────────────────────────────────────────────────┐
│  Developer pushes code to feature branch                │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│  Developer creates Pull Request → main                  │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│  CI Workflow (ci.yml) runs automatically                │
│  - Lint code                                            │
│  - Run tests                                            │
│  - Build images                                         │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
                 ┌────┴────┐
                 │  Pass?  │
                 └────┬────┘
                  Yes │ No
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
   ┌────────┐   ┌──────────┐   ┌────────┐
   │ Merge  │   │  Block   │   │  Fix   │
   │ to main│   │  Merge   │   │ Issues │
   └────┬───┘   └──────────┘   └───┬────┘
        │                           │
        │                           └─────┐
        ▼                                 │
┌─────────────────────────────────────────▼───────────────┐
│  CD Workflow (deploy.yml) runs automatically            │
│  - Configure AWS (via OIDC)                             │
│  - Create .env from secrets                             │
│  - Deploy to EC2                                        │
│  - Restart containers                                   │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│  Application live at http://<EC2_IP>                    │
└─────────────────────────────────────────────────────────┘
```

---

## 🔑 GitHub OIDC Setup

**Why OIDC?**
- ✅ No long-lived AWS access keys in GitHub
- ✅ Temporary credentials generated per workflow run
- ✅ More secure - credentials expire automatically
- ✅ Easier rotation - change IAM policy, not secrets

**How it works:**
```
GitHub Actions → OIDC Token → AWS STS → Temporary Credentials → Deploy
```

**Setup (done in Terraform):**
1. Create OIDC identity provider in AWS
2. Create IAM role with trust policy for your GitHub repo
3. Add permissions: `ec2:DescribeInstances`, `ssm:SendCommand`
4. Store role ARN in GitHub Secrets

---

## 📝 Workflow Examples

### CI Workflow (`ci.yml`) - Example Structure
```yaml
name: CI - Test and Build

on:
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install dependencies
        run: |
          cd backend && npm install
          cd ../frontend && npm install
      - name: Run tests
        run: |
          cd backend && npm test
          cd ../frontend && npm test
```

### CD Workflow (`deploy.yml`) - Example Structure
```yaml
name: CD - Deploy to EC2

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
      contents: read
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
      - name: Deploy to EC2
        run: |
          # Use SSM or SSH to deploy
          # Create .env file
          # Run deploy script
```

---

## 🧪 Testing Workflows Locally

### Using Act (GitHub Actions locally)
```bash
# Install act
brew install act  # macOS
# or
choco install act-cli  # Windows

# Run CI workflow
act pull_request

# Run CD workflow (dry run)
act push --dry-run
```

---

## 📊 Monitoring Deployments

### View Workflow Runs
```
GitHub Repo → Actions Tab → Select workflow
```

### Check Deployment Logs
```bash
# SSH to EC2
ssh ubuntu@<EC2_IP>

# View Docker logs
docker compose logs -f

# View deployment history
cat /var/log/cloud-init-output.log
```

---

## ⚠️ Troubleshooting

### Workflow fails at AWS authentication
- Check `AWS_ROLE_ARN` is correct
- Verify IAM trust policy allows your repo
- Ensure `id-token: write` permission is set

### Deployment fails
- Check `.env` file was created on EC2
- Verify security group allows SSM/SSH
- Check EC2 instance is running: `aws ec2 describe-instances`

### Tests fail
- Run tests locally first: `npm test`
- Check if dependencies are up to date
- Review error logs in Actions tab

---

## 📚 Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS Actions - Configure Credentials](https://github.com/aws-actions/configure-aws-credentials)
- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)

---

**Status:** 📝 Phase 1 - Directory structure created  
**Next:** Phase 5 & 6 - Create workflow files

See `../TERRAFORM_CI_CD_PLAN.md` for the complete deployment plan.
