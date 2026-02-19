# =============================================================================
# Monitoring Server Security Group
# =============================================================================
# Scope: ONLY the monitoring SG resource + its OWN ingress/egress rules.
#
# Rules defined here:
#   - Grafana    (3000) — operator IP → Grafana UI
#   - Prometheus (9090) — operator IP → Prometheus UI
#   - SSH        (22)   — operator IP → emergency shell access
#   - Node Exporter (9100) — self (monitoring SG → monitoring SG)
#   - All outbound
#
# Rules NOT defined here (see sg_rules.tf):
#   - Port 3001 on APP SG from monitoring SG → Prometheus scrapes /metrics
#   - Port 9100 on APP SG from monitoring SG → Prometheus scrapes Node Exporter
#
# Security rationale:
#   Grafana and Prometheus have no built-in auth hardening by default.
#   The SG is the primary access control — never open :3000/:9090 to 0.0.0.0/0.
# =============================================================================

resource "aws_security_group" "monitoring" {
  name_prefix = "${var.environment}-monitoring-"
  description = "Security group for Prometheus + Grafana Observations Server"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-monitoring-sg"
      Role = "observations-server"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Monitoring Server — Inbound Rules
# =============================================================================

# Grafana UI — port 3000
resource "aws_vpc_security_group_ingress_rule" "grafana" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Grafana dashboard - restricted to operator IP"

  from_port   = 3000
  to_port     = 3000
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_ssh_cidr)

  tags = { Name = "monitoring-grafana-inbound" }
}

# Prometheus UI — port 9090
# No built-in auth — SG is the only guard. Never open to 0.0.0.0/0.
resource "aws_vpc_security_group_ingress_rule" "prometheus_ui" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Prometheus UI - restricted to operator IP"

  from_port   = 9090
  to_port     = 9090
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_ssh_cidr)

  tags = { Name = "monitoring-prometheus-inbound" }
}

# Alertmanager UI — port 9093
# No built-in auth — SG is the only guard. Never open to 0.0.0.0/0.
resource "aws_vpc_security_group_ingress_rule" "alertmanager_ui" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Alertmanager UI - restricted to operator IP"

  from_port   = 9093
  to_port     = 9093
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_ssh_cidr)

  tags = { Name = "monitoring-alertmanager-inbound" }
}

# SSH — port 22
resource "aws_vpc_security_group_ingress_rule" "monitoring_ssh" {
  security_group_id = aws_security_group.monitoring.id
  description       = "SSH emergency access - restricted to operator IP"

  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = join(",", var.allowed_ssh_cidr)

  tags = { Name = "monitoring-ssh-inbound" }
}

# Node Exporter — port 9100 (self-scrape)
# Prometheus runs on the same host and scrapes localhost:9100 directly.
# This SG-to-self rule handles future multi-instance setups cleanly.
resource "aws_vpc_security_group_ingress_rule" "monitoring_node_exporter_self" {
  security_group_id            = aws_security_group.monitoring.id
  description                  = "Node Exporter - self-scrape within monitoring SG"
  referenced_security_group_id = aws_security_group.monitoring.id

  from_port   = 9100
  to_port     = 9100
  ip_protocol = "tcp"

  tags = { Name = "monitoring-node-exporter-self" }
}

# =============================================================================
# Monitoring Server — Outbound Rules
# =============================================================================

# All outbound: package installs, AWS API calls, scraping app server targets.
resource "aws_vpc_security_group_egress_rule" "monitoring_all_outbound" {
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow all outbound (package installs, AWS API, scraping)"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = { Name = "monitoring-all-outbound" }
}
