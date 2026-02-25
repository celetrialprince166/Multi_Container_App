 # =============================================================================
 # ECS Cluster (Fargate) for Notes App
 # =============================================================================
 # Purpose: Provide an ECS cluster to run the existing backend/frontend/proxy
 # containers on Fargate. The service below wires the tasks to the ALB.
 # =============================================================================

resource "aws_ecs_cluster" "notes_app" {
  name = "${var.environment}-notes-app-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-ecs-cluster"
      Role = "ecs-cluster"
    }
  )
}

# =============================================================================
# Bootstrap Task Definition (initial revision)
# =============================================================================
# Purpose: Create an initial task definition so the ECS service can be created.
# Jenkins will register new revisions per build; we configure the service to
# ignore changes to task_definition so Terraform does not fight CI.
# =============================================================================

resource "aws_ecs_task_definition" "notes_app_bootstrap" {
  family                   = "notes-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "proxy"
      image     = "public.ecr.aws/nginx/nginx:latest"
      essential = true
      portMappings = [{
        containerPort = 80
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/notes-app/ecs/proxy"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "proxy"
        }
      }
    }
  ])
}

 # =============================================================================
 # ECS Service for Notes App
 # =============================================================================

resource "aws_ecs_service" "notes_app" {
  name            = "${var.environment}-notes-app-service"
  cluster         = aws_ecs_cluster.notes_app.id
  task_definition = aws_ecs_task_definition.notes_app_bootstrap.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 120

  network_configuration {
    subnets          = data.aws_subnets.default_vpc.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.notes_app.arn
    container_name   = "proxy"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-service"
      Role = "ecs-service"
    }
  )

  depends_on = [
    aws_lb_listener.http,
    aws_ecs_task_definition.notes_app_bootstrap
  ]
}


