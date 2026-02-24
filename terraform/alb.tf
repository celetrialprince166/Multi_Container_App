 # =============================================================================
 # Application Load Balancer for ECS Fargate
 # =============================================================================
 # Purpose: Public entry point for the Notes App when running on ECS Fargate.
 # For now this defines:
 #   - ALB (internet-facing) in the default VPC subnets
 #   - Target group for ECS tasks (IP target type, port 80)
 #   - HTTP listener forwarding to the target group
 #
 # The ECS service will attach to this target group in a later step.
 # =============================================================================

 data "aws_subnets" "default_vpc" {
   filter {
     name   = "vpc-id"
     values = [data.aws_vpc.default.id]
   }
 }

 resource "aws_lb" "notes_app" {
   name               = "${var.environment}-notes-app-alb"
   load_balancer_type = "application"
   internal           = false

   security_groups = [aws_security_group.ecs_alb.id]
   subnets         = data.aws_subnets.default_vpc.ids

   enable_deletion_protection = false

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-app-alb"
       Role = "public-entrypoint"
     }
   )
 }

 resource "aws_lb_target_group" "notes_app" {
   name        = "${var.environment}-notes-app-tg"
   port        = 80
   protocol    = "HTTP"
   target_type = "ip" # required for Fargate
   vpc_id      = data.aws_vpc.default.id

   health_check {
     enabled             = true
     healthy_threshold   = 3
     unhealthy_threshold = 3
     timeout             = 5
     interval            = 30
     path                = "/nginx-health"
     matcher             = "200"
   }

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-app-tg"
       Role = "ecs-target-group"
     }
   )
 }

 resource "aws_lb_listener" "http" {
   load_balancer_arn = aws_lb.notes_app.arn
   port              = 80
   protocol          = "HTTP"

   default_action {
     type             = "forward"
     target_group_arn = aws_lb_target_group.notes_app.arn
   }
 }

