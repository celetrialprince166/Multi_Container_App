 # =============================================================================
 # ECS Security Groups (Tasks + ALB)
 # =============================================================================
 # Purpose: Network boundaries for ECS Fargate tasks and their public ALB.
 # - ecs_tasks SG: attached to ECS tasks (backend/frontend/proxy task definition)
 # - ecs_alb   SG: attached to the public Application Load Balancer
 # Cross-SG rules (ALB → tasks) are defined in sg_rules.tf alongside other
 # inter-service relationships.
 # =============================================================================

 resource "aws_security_group" "ecs_tasks" {
   name_prefix = "${var.environment}-notes-app-ecs-tasks-"
   description = "Security group for Notes App ECS tasks"
   vpc_id      = data.aws_vpc.default.id

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-app-ecs-tasks-sg"
       Role = "ecs-tasks"
     }
   )

   lifecycle {
     create_before_destroy = true
   }
 }

 resource "aws_security_group" "ecs_alb" {
   name_prefix = "${var.environment}-notes-app-ecs-alb-"
   description = "Security group for Notes App public ALB"
   vpc_id      = data.aws_vpc.default.id

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-app-ecs-alb-sg"
       Role = "ecs-alb"
     }
   )

   lifecycle {
     create_before_destroy = true
   }
 }

 # ALB — inbound HTTP (80) from internet
 resource "aws_vpc_security_group_ingress_rule" "ecs_alb_http" {
   security_group_id = aws_security_group.ecs_alb.id
   description       = "HTTP traffic from internet to ECS ALB"

   from_port   = 80
   to_port     = 80
   ip_protocol = "tcp"
   cidr_ipv4   = join(",", var.allowed_http_cidr)

   tags = { Name = "ecs-alb-http-inbound" }
 }

 # ALB — outbound all (to ECS tasks and internet)
 resource "aws_vpc_security_group_egress_rule" "ecs_alb_all_outbound" {
   security_group_id = aws_security_group.ecs_alb.id
   description       = "Allow all outbound from ECS ALB"

   ip_protocol = "-1"
   cidr_ipv4   = "0.0.0.0/0"

   tags = { Name = "ecs-alb-all-outbound" }
 }

resource "aws_vpc_security_group_ingress_rule" "ecs_alb_test" {
  security_group_id = aws_security_group.ecs_alb.id
  description       = "HTTP test listener traffic (8080) from internet to ECS ALB"

  from_port   = 8080
  to_port     = 8080
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"

  tags = { Name = "ecs-alb-test-http-inbound" }
}

 # ECS tasks — outbound all (pull images, call external APIs, etc.)
 resource "aws_vpc_security_group_egress_rule" "ecs_tasks_all_outbound" {
   security_group_id = aws_security_group.ecs_tasks.id
   description       = "Allow all outbound from ECS tasks"

   ip_protocol = "-1"
   cidr_ipv4   = "0.0.0.0/0"

   tags = { Name = "ecs-tasks-all-outbound" }
 }

