# =============================================================================
# Terraform Variables
# =============================================================================
# Purpose: Input variables for infrastructure configuration
# Usage: Set values in terraform.tfvars or via command line
# =============================================================================

# =============================================================================
# AWS Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., eu-west-1, eu-west-2)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_owner" {
  description = "Name or email of the project owner"
  type        = string
  default     = "DevOps Team"
}

variable "git_repo_url" {
  description = "Git repository URL for the application"
  type        = string
  default     = "https://github.com/celetrialprince166/Multi_Container_App"
}

# =============================================================================
# EC2 Instance Configuration
# =============================================================================

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^t[2-3]\\.(nano|micro|small|medium|large)", var.instance_type))
    error_message = "Instance type must be a valid t2 or t3 instance type."
  }
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "Root volume size must be between 8 and 100 GB."
  }
}

variable "root_volume_type" {
  description = "Type of root EBS volume"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3"], var.root_volume_type)
    error_message = "Root volume type must be gp2 or gp3."
  }
}

variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed to SSH to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"] # CHANGE THIS! Restrict to your IP

  validation {
    condition     = length(var.allowed_ssh_cidr) > 0
    error_message = "At least one CIDR block must be specified for SSH access."
  }
}

variable "allowed_http_cidr" {
  description = "CIDR blocks allowed to access HTTP/HTTPS"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Allow public access
}

# =============================================================================
# Application Configuration
# =============================================================================

variable "app_directory" {
  description = "Directory where application will be deployed on EC2"
  type        = string
  default     = "/opt/notes-app"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "celetrialprince166"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "Multi_Container_App"
}

# =============================================================================
# GitHub OIDC Configuration
# =============================================================================

variable "github_oidc_thumbprint" {
  description = "Thumbprint for GitHub OIDC provider"
  type        = list(string)
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  # This is GitHub's current thumbprint, but verify: 
  # https://github.blog/changelog/2022-01-13-github-actions-update-on-oidc-based-deployments-to-aws/
}

# =============================================================================
# Tags
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "grafana_admin_password" {
  description = "Admin password for Grafana UI (change before applying)"
  type        = string
  sensitive   = true
  default     = "NotesApp@Grafana2024!"

  validation {
    condition     = length(var.grafana_admin_password) >= 8
    error_message = "Grafana admin password must be at least 8 characters."
  }
}

variable "slack_webhook_url" {
  description = "Slack Incoming Webhook URL for Alertmanager notifications"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.slack_webhook_url == "" || can(regex("^https://hooks\\.slack\\.com/", var.slack_webhook_url))
    error_message = "Slack webhook URL must start with https://hooks.slack.com/ or be empty."
  }
}
