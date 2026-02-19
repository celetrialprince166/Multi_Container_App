# =============================================================================
# Observations Server EC2 Instance
# =============================================================================
# Purpose: Single EC2 instance running Prometheus + Grafana + Node Exporter
#          via Docker Compose. Bootstrapped entirely by monitoring_user_data.sh.
#
# Design decisions:
#   - t3.small: 2 vCPU, 2 GB RAM — sufficient for Prometheus + Grafana in a lab.
#     Prometheus with 15s scrape interval and 4 targets uses ~200–400 MB RAM.
#   - Same Ubuntu 22.04 AMI as the app server (consistent tooling).
#   - IMDSv2 required (security hardening — prevents SSRF metadata attacks).
#   - EBS encrypted (data at rest protection for Prometheus TSDB).
#   - Separate IAM role with CloudWatchReadOnlyAccess only (least privilege).
# =============================================================================

# ── IAM Role for Monitoring Server ───────────────────────────────────────────
resource "aws_iam_role" "monitoring" {
  name_prefix        = "${var.environment}-monitoring-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for Observations Server (Prometheus + Grafana)"

  tags = merge(
    local.common_tags,
    { Name = "${var.environment}-monitoring-role" }
  )
}

# CloudWatch read-only: allows querying metrics/logs from the Grafana CloudWatch
# datasource plugin (optional future use). Monitoring server does NOT write logs.
resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch_read" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# SSM: allows connecting to the monitoring server via Session Manager
# (no SSH key needed for emergency access)
resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitoring" {
  name_prefix = "${var.environment}-monitoring-"
  role        = aws_iam_role.monitoring.name

  tags = merge(
    local.common_tags,
    { Name = "${var.environment}-monitoring-profile" }
  )
}

# ── TLS Key Pair for Monitoring Server ───────────────────────────────────────
resource "tls_private_key" "monitoring" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "monitoring" {
  key_name_prefix = "${var.environment}-monitoring-"
  public_key      = tls_private_key.monitoring.public_key_openssh

  tags = merge(
    local.common_tags,
    { Name = "${var.environment}-monitoring-key" }
  )
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "monitoring" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small" # 2 vCPU, 2 GB RAM — adequate for Prometheus + Grafana

  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name
  key_name               = aws_key_pair.monitoring.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20 # 20 GB: OS + Docker images + Prometheus TSDB (15 days)
    delete_on_termination = true
    encrypted             = true # Encrypt Prometheus time-series data at rest

    tags = merge(
      local.common_tags,
      { Name = "${var.environment}-monitoring-root-volume" }
    )
  }

  # Bootstrap script — installs Docker, writes all configs, starts the stack.
  # Terraform injects app_server_private_ip and grafana_admin_password.
  user_data = templatefile("${path.module}/monitoring_user_data.sh", {
    app_server_private_ip  = aws_instance.notes_app.private_ip
    grafana_admin_password = var.grafana_admin_password
    slack_webhook_url      = var.slack_webhook_url
    aws_region             = var.aws_region
    git_repo_url           = var.git_repo_url
  })

  # IMDSv2 required — prevents SSRF attacks from reading instance metadata
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring = true # Enable detailed CloudWatch metrics (1-minute granularity)

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-monitoring-server"
      Role = "observations-server"
    }
  )

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [
    aws_iam_instance_profile.monitoring,
    aws_security_group.monitoring,
    aws_key_pair.monitoring,
    # Ensure app server exists so its private IP is available for templatefile()
    aws_instance.notes_app,

  ]
}
