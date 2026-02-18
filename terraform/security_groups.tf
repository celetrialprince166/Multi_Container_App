# =============================================================================
# Application Server Security Group
# =============================================================================
# Scope: ONLY the SG resource + its OWN ingress/egress rules.
#
# Rules defined here:
#   - HTTP  (80)  — public internet → Nginx proxy
#   - HTTPS (443) — public internet → Nginx proxy (future TLS)
#   - SSH   (22)  — operator IP     → emergency shell access
#   - All outbound
#
# Rules NOT defined here (see sg_rules.tf):
#   - Port 3001 from monitoring SG  → Prometheus scrapes /metrics
#   - Port 9100 from monitoring SG  → Prometheus scrapes Node Exporter
#
# Why separate? Cross-SG rules depend on BOTH SGs existing first.
# Keeping them in sg_rules.tf avoids circular dependency and makes
# inter-service relationships explicit and easy to audit.
# =============================================================================

resource "aws_security_group" "notes_app" {
  name_prefix = "${var.environment}-notes-app-"
  description = "Security group for Notes Application EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-sg"
      Role = "application-server"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# App Server — Inbound Rules
# =============================================================================

# HTTP — port 80
# Public-facing: Nginx proxy receives all user traffic here.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.notes_app.id
  description       = "HTTP traffic from internet to Nginx proxy"

  from_port   = local.app_port
  to_port     = local.app_port
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_http_cidr)

  tags = { Name = "app-http-inbound" }
}

# HTTPS — port 443
# Reserved for future TLS termination at Nginx (cert not yet configured).
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.notes_app.id
  description       = "HTTPS traffic from internet to Nginx proxy (future TLS)"

  from_port   = local.https_port
  to_port     = local.https_port
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_http_cidr)

  tags = { Name = "app-https-inbound" }
}

# SSH — port 22
# Restricted to operator CIDR. Prefer SSM Session Manager for day-to-day access.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.notes_app.id
  description       = "SSH emergency access - restricted to operator IP"

  from_port   = local.ssh_port
  to_port     = local.ssh_port
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_ssh_cidr)

  tags = { Name = "app-ssh-inbound" }
}

# =============================================================================
# App Server — Outbound Rules
# =============================================================================

# All outbound: needed for apt-get, Docker pulls from ECR, AWS API calls.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.notes_app.id
  description       = "Allow all outbound (ECR pulls, AWS API, package installs)"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = { Name = "app-all-outbound" }
}
