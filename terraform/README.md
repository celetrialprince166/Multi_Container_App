# Terraform Infrastructure

This directory contains Terraform configuration files for deploying the Notes application infrastructure on AWS.

## 📁 Directory Structure

```
terraform/
├── main.tf                 # Provider configuration, backend
├── variables.tf            # Input variables
├── outputs.tf              # Output values (IP, DNS, etc.)
├── ec2.tf                  # EC2 instance configuration
├── security_groups.tf      # Security group rules
├── iam.tf                  # IAM roles and policies
├── user_data.sh            # EC2 bootstrap script
└── README.md               # This file
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI** installed and configured
2. **Terraform** installed (v1.0+)
3. **AWS Account** with appropriate permissions

### Step 1: Configure Variables

Create a `terraform.tfvars` file (don't commit this!):

```hcl
aws_region       = "eu-west-1"
environment      = "dev"
instance_type    = "t3.small"
key_name         = "your-ec2-key-pair-name"
allowed_ssh_cidr = ["YOUR_IP/32"]
```

### Step 2: Initialize Terraform

```bash
cd terraform
terraform init
```

### Step 3: Plan Infrastructure

```bash
terraform plan
```

### Step 4: Apply Infrastructure

```bash
terraform apply
```

### Step 5: Get Outputs

```bash
terraform output
```

---

## 📝 Configuration Files (To Be Created in Phase 3)

### `main.tf`
- AWS provider configuration
- Terraform backend (S3 for state storage)
- Local variables

### `variables.tf`
- Input variables for customization
- Default values
- Variable descriptions

### `ec2.tf`
- EC2 instance resource
- AMI selection (Ubuntu 22.04)
- Instance type
- User data script
- Tags

### `security_groups.tf`
- Security group for EC2
- Inbound rules (80, 443, 22)
- Outbound rules (allow all)

### `iam.tf`
- IAM instance profile for EC2
- IAM role for GitHub Actions (OIDC)
- Policies for SSM access

### `user_data.sh`
- Bootstrap script (runs once on first boot)
- Installs Docker and Docker Compose
- Sets up application directory

### `outputs.tf`
- EC2 public IP
- EC2 public DNS
- Instance ID
- Security group ID

---

## 🔐 Secrets Management

**This setup does NOT use AWS Secrets Manager.**

Secrets are managed via:
1. **GitHub Secrets** - Store sensitive values
2. **CI/CD Pipeline** - Creates `.env` on EC2
3. **Docker Compose** - Reads `.env` file

---

## 🌍 Terraform State

### Local State (Default)
State file stored locally: `terraform.tfstate`

⚠️ **Not recommended for teams or production!**

### Remote State (Recommended)
Use S3 backend with DynamoDB for state locking:

```hcl
# In main.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "notes-app/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

---

## 🎯 Resources Created

| Resource | Type | Purpose |
|----------|------|---------|
| EC2 Instance | `t3.small` | Application server |
| Security Group | Firewall | Allow HTTP, HTTPS, SSH |
| IAM Role (EC2) | Permissions | SSM access |
| IAM Role (GitHub) | Permissions | Deployment access |
| EBS Volume | Storage | Root volume (8-20 GB) |

---

## 💰 Estimated Costs

| Resource | Monthly Cost (eu-west-1) |
|----------|--------------------------|
| EC2 t3.small (24/7) | ~$15.00 |
| EBS gp3 (20 GB) | ~$1.60 |
| Data Transfer | ~$0.50 |
| **Total** | **~$17/month** |

💡 **Cost Savings:**
- Stop EC2 when not in use: ~$0.50/day when stopped
- Use AWS Free Tier (750 hours/month t2.micro or t3.micro for first 12 months)

---

## 🛠️ Common Commands

```bash
# Initialize
terraform init

# Format code
terraform fmt

# Validate configuration
terraform validate

# Plan changes
terraform plan

# Apply changes
terraform apply

# Show outputs
terraform output

# Show current state
terraform show

# Destroy everything
terraform destroy
```

---

## 🔍 Debugging

### Check Terraform Version
```bash
terraform version
```

### Check AWS Credentials
```bash
aws sts get-caller-identity
```

### View Instance User Data Logs (on EC2)
```bash
ssh ubuntu@<EC2_IP>
sudo cat /var/log/cloud-init-output.log
```

---

## 📚 Next Steps

1. **Phase 2:** Create Terraform files (we'll do this together!)
2. **Phase 3:** Run `terraform apply`
3. **Phase 4:** Set up GitHub Actions CI/CD
4. **Phase 5:** Deploy application

---

## ⚠️ Important Notes

- Never commit `terraform.tfvars` (contains sensitive data)
- Never commit `.terraform/` directory
- Never commit `terraform.tfstate` (may contain secrets)
- Always review `terraform plan` before `apply`
- Use `terraform destroy` carefully (deletes everything!)

---

**Status:** 📝 Phase 1 - Directory structure created  
**Next:** Phase 3 - Create Terraform configuration files

See `../TERRAFORM_CI_CD_PLAN.md` for the complete deployment plan.
