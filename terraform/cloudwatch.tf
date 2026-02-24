 # =============================================================================
 # CloudWatch Log Groups for ECS Tasks
 # =============================================================================
 # Purpose: Pre-create log groups used by the ECS task definition's awslogs
 # driver so we can set retention and tags explicitly.
 # =============================================================================

 resource "aws_cloudwatch_log_group" "ecs_backend" {
   name              = "/notes-app/ecs/backend"
   retention_in_days = 30

   tags = merge(
     local.common_tags,
     {
       Name = "/notes-app/ecs/backend"
       Role = "ecs-backend-logs"
     }
   )
 }

 resource "aws_cloudwatch_log_group" "ecs_frontend" {
   name              = "/notes-app/ecs/frontend"
   retention_in_days = 30

   tags = merge(
     local.common_tags,
     {
       Name = "/notes-app/ecs/frontend"
       Role = "ecs-frontend-logs"
     }
   )
 }

 resource "aws_cloudwatch_log_group" "ecs_proxy" {
   name              = "/notes-app/ecs/proxy"
   retention_in_days = 30

   tags = merge(
     local.common_tags,
     {
       Name = "/notes-app/ecs/proxy"
       Role = "ecs-proxy-logs"
     }
   )
 }

