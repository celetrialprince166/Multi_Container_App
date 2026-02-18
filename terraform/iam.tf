# =============================================================================
# IAM Roles and Policies
# =============================================================================
# Purpose: Define IAM roles for EC2 and GitHub Actions
# Security: Principle of least privilege
# =============================================================================

# =============================================================================
# EC2 Instance Role (for SSM and basic operations)
# =============================================================================

# IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_instance_role" {
  name_prefix        = "${var.environment}-notes-app-ec2-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for Notes App EC2 instance"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-ec2-role"
    }
  )
}

# Trust policy for EC2
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed policy for SSM
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach ECR read-only for pulling images
resource "aws_iam_role_policy_attachment" "ec2_ecr" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Attach AWS managed policy for CloudWatch (always enabled for awslogs driver)
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Inline policy: allow the awslogs Docker log driver to create log groups
# and push log events to CloudWatch Logs.
# CloudWatchAgentServerPolicy covers the agent; this covers the Docker driver.
resource "aws_iam_role_policy" "ec2_cloudwatch_logs" {
  name = "cloudwatch-logs-docker-driver"
  role = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DockerAwslogsDriver"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/notes-app/*"
      }
    ]
  })
}

# Instance Profile (required to attach role to EC2)
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${var.environment}-notes-app-"
  role        = aws_iam_role.ec2_instance_role.name

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-profile"
    }
  )
}

# =============================================================================
# GitHub OIDC Provider (for GitHub Actions authentication)
# =============================================================================

# Create GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprint

  tags = merge(
    local.common_tags,
    {
      Name = "github-oidc-provider"
    }
  )
}

# =============================================================================
# GitHub Actions Deployment Role
# =============================================================================

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name_prefix        = "${var.environment}-github-actions-"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  description        = "IAM role for GitHub Actions to deploy to EC2"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-github-actions-role"
    }
  )
}

# Trust policy for GitHub Actions
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Allow from specific repo and branch
      values = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

# Custom policy for GitHub Actions deployment
resource "aws_iam_policy" "github_actions_deploy" {
  name_prefix = "${var.environment}-github-deploy-"
  description = "Policy for GitHub Actions to deploy to EC2"
  policy      = data.aws_iam_policy_document.github_actions_policy.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-github-deploy-policy"
    }
  )
}

# Policy document for GitHub Actions
data "aws_iam_policy_document" "github_actions_policy" {
  # Allow describing EC2 instances
  statement {
    sid    = "DescribeEC2"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags"
    ]

    resources = ["*"]
  }

  # Allow SSM commands for deployment
  statement {
    sid    = "SSMCommands"
    effect = "Allow"

    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations"
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["NotesApp"]
    }
  }

  # Allow ECR push (build and push images)
  statement {
    sid    = "ECRPush"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ECRImagePush"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]

    resources = [
      aws_ecr_repository.backend.arn,
      aws_ecr_repository.frontend.arn,
      aws_ecr_repository.proxy.arn
    ]
  }
}

# Attach policy to GitHub Actions role
resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}
