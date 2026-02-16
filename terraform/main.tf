# =============================================================================
# Main Terraform Configuration
# =============================================================================
# Purpose: Provider configuration and backend setup
# Project: Notes Application - Docker to AWS EC2 Migration
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Optional: S3 Backend for remote state
  # Uncomment and configure when ready for production
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "notes-app/terraform.tfstate"
  #   region         = "eu-west-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# =============================================================================
# AWS Provider Configuration
# =============================================================================
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "NotesApp"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.project_owner
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

# Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# =============================================================================
# Local Variables
# =============================================================================
locals {
  common_tags = {
    Application = "notes-app"
    Terraform   = "true"
    GitRepo     = var.git_repo_url
  }

  app_port  = 80
  ssh_port  = 22
  https_port = 443
}
