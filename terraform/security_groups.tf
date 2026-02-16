# =============================================================================
# Security Groups
# =============================================================================
# Purpose: Define firewall rules for EC2 instance
# Best Practice: Principle of least privilege
# =============================================================================

resource "aws_security_group" "notes_app" {
  name_prefix = "${var.environment}-notes-app-"
  description = "Security group for Notes Application EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Ingress Rules (Inbound Traffic)
# =============================================================================

# HTTP - Port 80
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.notes_app.id
  description       = "Allow HTTP traffic from anywhere"

  from_port   = local.app_port
  to_port     = local.app_port
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_http_cidr)

  tags = {
    Name = "http-inbound"
  }
}

# HTTPS - Port 443 (for future SSL/TLS)
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.notes_app.id
  description       = "Allow HTTPS traffic from anywhere"

  from_port   = local.https_port
  to_port     = local.https_port
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_http_cidr)

  tags = {
    Name = "https-inbound"
  }
}

# SSH - Port 22 (for emergency access)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.notes_app.id
  description       = "Allow SSH access from specified IPs"

  from_port   = local.ssh_port
  to_port     = local.ssh_port
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_ssh_cidr)

  tags = {
    Name = "ssh-inbound"
  }
}

# =============================================================================
# Egress Rules (Outbound Traffic)
# =============================================================================

# Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.notes_app.id
  description       = "Allow all outbound traffic"

  ip_protocol = "-1" # All protocols
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}
