# =============================================================================
# Cross-Service Security Group Rules
# =============================================================================
# Purpose: Define ALL ingress rules that cross security group boundaries.
#
# Why a dedicated file?
#   Cross-SG rules depend on BOTH the source and destination SGs existing.
#   Putting them in either sg file creates hidden coupling — a reader of
#   security_groups.tf would not know that monitoring_sg.tf is also adding
#   rules to the app SG. This file makes all inter-service trust explicit
#   and is the SINGLE place to audit "what can talk to what".
#
# Naming convention: <source>_to_<destination>_<port/purpose>
#
# Current trust relationships:
#
#   monitoring SG ──port 3001──► app SG    (Prometheus scrapes /metrics)
#   monitoring SG ──port 9100──► app SG    (Prometheus scrapes Node Exporter)
#   ecs_alb SG   ──port 80───► ecs_tasks SG (ALB routes HTTP to ECS tasks)
#
# Future rules to add here (not yet implemented):
#   - RDS SG ← app SG port 5432 (if PostgreSQL moves to RDS)
#   - ALB SG → app SG port 3001 (if an ALB is added in front of EC2 host)
# =============================================================================

# =============================================================================
# Monitoring → App Server (Prometheus scraping)
# =============================================================================

# Allow Prometheus (on monitoring server) to scrape the NestJS /metrics endpoint.
# Port 3001 is the backend container port — NOT proxied by Nginx, so it is
# only reachable from within the VPC via this SG rule.
resource "aws_vpc_security_group_ingress_rule" "monitoring_to_app_metrics" {
  security_group_id            = aws_security_group.notes_app.id
  description                  = "Prometheus scrapes NestJS /metrics (port 3001) from monitoring server"
  referenced_security_group_id = aws_security_group.monitoring.id

  from_port   = 3001
  to_port     = 3001
  ip_protocol = "tcp"

  tags = {
    Name      = "monitoring-to-app-metrics"
    Direction = "monitoring→app"
    Purpose   = "prometheus-scrape"
  }
}

# Allow Prometheus (on monitoring server) to scrape Node Exporter on the app server.
# Node Exporter runs in host network mode on port 9100 and exposes EC2 OS metrics.
resource "aws_vpc_security_group_ingress_rule" "monitoring_to_app_node_exporter" {
  security_group_id            = aws_security_group.notes_app.id
  description                  = "Prometheus scrapes Node Exporter (port 9100) on app server"
  referenced_security_group_id = aws_security_group.monitoring.id

  from_port   = 9100
  to_port     = 9100
  ip_protocol = "tcp"

  tags = {
    Name      = "monitoring-to-app-node-exporter"
    Direction = "monitoring→app"
    Purpose   = "node-exporter-scrape"
  }
}

# =============================================================================
# ECS ALB → ECS Tasks (HTTP)
# =============================================================================

resource "aws_vpc_security_group_ingress_rule" "ecs_alb_to_ecs_tasks_http" {
  security_group_id            = aws_security_group.ecs_tasks.id
  description                  = "ALB forwards HTTP (80) to ECS tasks"
  referenced_security_group_id = aws_security_group.ecs_alb.id

  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = {
    Name      = "ecs-alb-to-ecs-tasks-http"
    Direction = "alb→ecs-tasks"
    Purpose   = "http-traffic"
  }
}

