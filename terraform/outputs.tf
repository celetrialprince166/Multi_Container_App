# =============================================================================
# Terraform Outputs
# =============================================================================
# Purpose: Export important values after infrastructure creation
# Usage: terraform output <output_name>
# =============================================================================

# =============================================================================
# EC2 Instance Outputs
# =============================================================================

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.notes_app.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.notes_app.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.notes_app.public_dns
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.notes_app.private_ip
}

output "instance_state" {
  description = "State of the EC2 instance"
  value       = aws_instance.notes_app.instance_state
}

# =============================================================================
# Application URLs
# =============================================================================

output "application_url" {
  description = "URL to access the Notes application"
  value       = "http://${aws_instance.notes_app.public_ip}"
}

output "application_dns_url" {
  description = "DNS-based URL to access the Notes application"
  value       = "http://${aws_instance.notes_app.public_dns}"
}

# =============================================================================
# SSH Connection
# =============================================================================

output "ssh_connection" {
  description = "SSH connection command (use: terraform output -raw ec2_private_key > key.pem && chmod 600 key.pem)"
  value       = "ssh -i key.pem ubuntu@${aws_instance.notes_app.public_ip}"
}

output "ssm_connection" {
  description = "SSM Session Manager connection command"
  value       = "aws ssm start-session --target ${aws_instance.notes_app.id} --region ${var.aws_region}"
}

# =============================================================================
# Security Group
# =============================================================================

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.notes_app.id
}

output "security_group_name" {
  description = "Name of the security group"
  value       = aws_security_group.notes_app.name
}

# =============================================================================
# IAM Roles
# =============================================================================

output "ec2_instance_role_arn" {
  description = "ARN of the EC2 instance IAM role"
  value       = aws_iam_role.ec2_instance_role.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role (for CI/CD)"
  value       = aws_iam_role.github_actions.arn
  sensitive   = false
}

# =============================================================================
# GitHub OIDC
# =============================================================================

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

# =============================================================================
# Resource Information
# =============================================================================

output "ami_id" {
  description = "AMI ID used for the instance"
  value       = data.aws_ami.ubuntu.id
}

output "ami_name" {
  description = "Name of the AMI used"
  value       = data.aws_ami.ubuntu.name
}

output "availability_zone" {
  description = "Availability zone where the instance is located"
  value       = aws_instance.notes_app.availability_zone
}

output "instance_type" {
  description = "Instance type"
  value       = aws_instance.notes_app.instance_type
}

# =============================================================================
# Helpful Commands
# =============================================================================

output "helpful_commands" {
  description = "Useful commands for working with this infrastructure"
  value = {
    "View instance logs"    = "aws ec2 get-console-output --instance-id ${aws_instance.notes_app.id} --region ${var.aws_region}"
    "Connect via SSM"       = "aws ssm start-session --target ${aws_instance.notes_app.id} --region ${var.aws_region}"
    "Check instance status" = "aws ec2 describe-instance-status --instance-ids ${aws_instance.notes_app.id} --region ${var.aws_region}"
    "Stop instance"         = "aws ec2 stop-instances --instance-ids ${aws_instance.notes_app.id} --region ${var.aws_region}"
    "Start instance"        = "aws ec2 start-instances --instance-ids ${aws_instance.notes_app.id} --region ${var.aws_region}"
    "View user-data logs"   = "ssh ubuntu@${aws_instance.notes_app.public_ip} 'sudo cat /var/log/user-data.log'"
  }
}

# =============================================================================
# Key Pair (for GitHub Secrets)
# =============================================================================

output "ec2_private_key" {
  description = "EC2 SSH private key - add to GitHub Secret SSH_PRIVATE_KEY (terraform output -raw ec2_private_key)"
  value       = tls_private_key.notes_app.private_key_pem
  sensitive   = true
}

output "key_pair_name" {
  description = "Name of the AWS key pair"
  value       = aws_key_pair.notes_app.key_name
}

# =============================================================================
# ECR Repositories (registry derived from account ID + region)
# =============================================================================

output "ecr_registry" {
  description = "ECR registry URL (derived from account ID and region)"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

output "ecr_backend_url" {
  description = "ECR URL for backend image"
  value       = "${aws_ecr_repository.backend.repository_url}:latest"
}

output "ecr_frontend_url" {
  description = "ECR URL for frontend image"
  value       = "${aws_ecr_repository.frontend.repository_url}:latest"
}

output "ecr_proxy_url" {
  description = "ECR URL for proxy image"
  value       = "${aws_ecr_repository.proxy.repository_url}:latest"
}

# =============================================================================
# GitHub Secrets (for CI/CD setup)
# =============================================================================

output "github_secrets_to_configure" {
  description = "GitHub Secrets - ECR_REGISTRY is derived in workflow from AWS account"
  value = {
    AWS_REGION      = var.aws_region
    AWS_ROLE_ARN    = aws_iam_role.github_actions.arn
    EC2_HOST        = aws_instance.notes_app.public_ip
    SSH_PRIVATE_KEY = "terraform output -raw ec2_private_key"
    # ECR_REGISTRY derived automatically (account_id.dkr.ecr.region.amazonaws.com)
    # Also add: DB_USERNAME, DB_PASSWORD, DB_NAME
  }
}

# =============================================================================
# Summary
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    environment     = var.environment
    region          = var.aws_region
    instance_id     = aws_instance.notes_app.id
    public_ip       = aws_instance.notes_app.public_ip
    application_url = "http://${aws_instance.notes_app.public_ip}"
    github_role_arn = aws_iam_role.github_actions.arn
    next_steps      = "1. Configure GitHub Secrets, 2. Push code to trigger deployment"
  }
}

# =============================================================================
# Monitoring Server Outputs
# =============================================================================

output "monitoring_server_ip" {
  description = "Public IP of the Observations Server (Prometheus + Grafana)"
  value       = aws_instance.monitoring.public_ip
}

output "prometheus_url" {
  description = "Prometheus UI URL"
  value       = "http://${aws_instance.monitoring.public_ip}:9090"
}

output "grafana_url" {
  description = "Grafana UI URL (login: admin / see grafana_admin_password variable)"
  value       = "http://${aws_instance.monitoring.public_ip}:3000"
}

output "monitoring_ssh_connection" {
  description = "SSH command for the monitoring server"
  value       = "ssh -i monitoring-key.pem ubuntu@${aws_instance.monitoring.public_ip}"
}

output "monitoring_private_key" {
  description = "Monitoring server SSH private key (terraform output -raw monitoring_private_key)"
  value       = tls_private_key.monitoring.private_key_pem
  sensitive   = true
}

# =============================================================================
# Security Services Outputs
# =============================================================================

output "cloudtrail_s3_bucket" {
  description = "S3 bucket storing CloudTrail audit logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_s3_bucket_arn" {
  description = "ARN of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}

output "observability_summary" {
  description = "Summary of observability and security resources"
  value = {
    prometheus_url       = "http://${aws_instance.monitoring.public_ip}:9090"
    grafana_url          = "http://${aws_instance.monitoring.public_ip}:3000"
    cloudwatch_log_group = "/notes-app/containers"
    cloudtrail_bucket    = aws_s3_bucket.cloudtrail.bucket
    guardduty_detector   = aws_guardduty_detector.main.id
    app_server_ip        = aws_instance.notes_app.public_ip
    monitoring_server_ip = aws_instance.monitoring.public_ip
  }
}

