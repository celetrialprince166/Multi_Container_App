# Terraform Setup Guide

## 🎯 Quick Start (Industry Standard Workflow)

### Prerequisites

1. **AWS Account** with admin or sufficient permissions
2. **AWS CLI** installed and configured
3. **Terraform** installed (v1.0+)
4. **GitHub Repository** created

---

## 📝 Step-by-Step Setup

### Step 1: Configure AWS Credentials

```bash
# Configure AWS CLI with your credentials
aws configure

# Verify credentials
aws sts get-caller-identity
```

**Expected Output:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

---

### Step 2: Create terraform.tfvars

```bash
cd terraform

# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars  # or use your preferred editor
```

**Minimum required changes:**
```hcl
aws_region = "eu-west-1"  # Your preferred region
github_org = "your-github-username"
github_repo = "docker_lab"

# IMPORTANT: Restrict SSH access to your IP
allowed_ssh_cidr = ["YOUR_IP/32"]  # Get your IP: curl ifconfig.me
```

---

### Step 3: Initialize Terraform

```bash
terraform init
```

**What this does:**
- Downloads AWS provider
- Initializes backend
- Creates `.terraform/` directory

**Expected Output:**
```
Terraform has been successfully initialized!
```

---

### Step 4: Validate Configuration

```bash
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

---

### Step 5: Format Code (Optional but Recommended)

```bash
terraform fmt -recursive
```

---

### Step 6: Plan Infrastructure

```bash
terraform plan
```

**What to look for:**
- Number of resources to create (should be ~15-20)
- No errors
- Review security group rules

**Expected Output:**
```
Plan: 15 to add, 0 to change, 0 to destroy.
```

---

### Step 7: Apply Infrastructure

```bash
terraform apply
```

**Type `yes` when prompted**

**What this creates:**
- EC2 instance (Ubuntu 22.04)
- Security group
- IAM roles (EC2 + GitHub Actions)
- GitHub OIDC provider

**Time:** ~2-3 minutes

---

### Step 8: Save Outputs

```bash
# View all outputs
terraform output

# Save specific outputs for GitHub Secrets
terraform output -raw instance_public_ip > ../ec2_ip.txt
terraform output -raw github_actions_role_arn > ../github_role_arn.txt
terraform output -raw instance_id > ../instance_id.txt
```

---

## 📊 Verify Deployment

### Check EC2 Instance

```bash
# Get instance ID
terraform output instance_id

# Check instance status
aws ec2 describe-instance-status \
  --instance-ids $(terraform output -raw instance_id) \
  --region us-east-1
```

### Check User Data Logs (Bootstrap Script)

```bash
# Via SSM (no SSH key needed)
aws ssm start-session \
  --target $(terraform output -raw instance_id) \
  --region us-east-1

# Once connected, view logs
sudo cat /var/log/user-data.log
```

### Access Application (After Deployment)

```bash
# Get application URL
terraform output application_url

# Open in browser or curl
curl $(terraform output -raw application_url)
```

---

## 🔐 Configure GitHub Secrets

After Terraform apply, configure these in GitHub:

**Repository → Settings → Secrets and variables → Actions**

| Secret Name | Get Value From |
|-------------|----------------|
| `AWS_REGION` | `terraform output -raw aws_region` or from tfvars |
| `AWS_ROLE_ARN` | `terraform output -raw github_actions_role_arn` |
| `EC2_INSTANCE_ID` | `terraform output -raw instance_id` |
| `EC2_HOST` | `terraform output -raw instance_public_ip` |
| `DB_USERNAME` | Your choice (e.g., `notesapp_admin`) |
| `DB_PASSWORD` | Strong password (20+ chars) |
| `DB_NAME` | Your choice (e.g., `notesdb`) |

---

## 🛠️ Common Commands

### View Current State

```bash
terraform show
```

### View Specific Output

```bash
terraform output instance_public_ip
terraform output github_actions_role_arn
```

### Refresh State (if resources changed outside Terraform)

```bash
terraform refresh
```

### Destroy Infrastructure

```bash
terraform destroy
```

⚠️ **Warning:** This will delete ALL resources created by Terraform!

---

## 🐛 Troubleshooting

### Error: Invalid AWS Credentials

```bash
# Check credentials
aws sts get-caller-identity

# Reconfigure if needed
aws configure
```

### Error: Terraform Lock File

```bash
# Remove lock if stuck
rm .terraform.lock.hcl
terraform init -upgrade
```

### Error: Security Group Already Exists

```bash
# Import existing security group
terraform import aws_security_group.notes_app sg-xxxxxxxxx
```

### Error: Instance Not Accessible

```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw security_group_id)

# Check instance status
aws ec2 describe-instance-status \
  --instance-ids $(terraform output -raw instance_id)
```

---

## 📈 Cost Estimation

| Resource | Monthly Cost (us-east-1) |
|----------|--------------------------|
| EC2 t3.small (24/7) | ~$15.00 |
| EBS gp3 (20 GB) | ~$1.60 |
| Data Transfer | ~$0.50 |
| **Total** | **~$17/month** |

**Save money:**
- Stop instance when not in use: `aws ec2 stop-instances --instance-ids <instance-id>`
- Use t3.micro if eligible for free tier

---

## 🔄 Updating Infrastructure

### Update Variables

```bash
# Edit terraform.tfvars
nano terraform.tfvars

# Plan changes
terraform plan

# Apply changes
terraform apply
```

### Update Terraform Code

```bash
# After modifying .tf files
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

## 📚 Next Steps

1. ✅ Infrastructure created
2. **Configure GitHub Secrets** (see above)
3. **Create CI/CD workflows** (`.github/workflows/`)
4. **Push code** to trigger deployment
5. **Access application** at `http://<EC2_IP>`

---

## 🔗 Useful Links

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EC2 User Data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- [GitHub OIDC for AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)

---

**Status:** Ready to deploy infrastructure! 🚀

Run `terraform apply` when ready.
