// =============================================================================
// CodeDeploy Application & Deployment Group for ECS Blue/Green
// =============================================================================
// Purpose:
//   - Define an ECS-aware CodeDeploy application and deployment group that
//     orchestrate blue/green deployments for the Notes App ECS service.
//   - Attach the ALB blue/green target group pair and production/test
//     listeners so CodeDeploy can manage traffic shifting.
// Notes:
//   - Uses the Linear10PercentEvery1Minutes deployment config, with
//     auto-rollback enabled on deployment failure or 5xx CloudWatch alarms.
// =============================================================================

resource "aws_codedeploy_app" "notes_app" {
  name             = "${var.environment}-notes-app"
  compute_platform = "ECS"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-codedeploy-app"
      Role = "codedeploy-app"
    }
  )
}

resource "aws_codedeploy_deployment_group" "notes_app" {
  app_name              = aws_codedeploy_app.notes_app.name
  deployment_group_name = "${var.environment}-notes-app-dg"
  service_role_arn      = aws_iam_role.codedeploy_ecs.arn

  deployment_config_name = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"

  ecs_service {
    cluster_name = aws_ecs_cluster.notes_app.name
    service_name = aws_ecs_service.notes_app.name
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.alb_5xx.alarm_name]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      # Let deployments continue immediately without a manual pause.
      # When action_on_timeout is CONTINUE_DEPLOYMENT, wait_time_in_minutes
      # must NOT be specified for ECS blue/green.
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.test.arn]
      }

      target_group {
        name = aws_lb_target_group.notes_app.name
      }

      target_group {
        name = aws_lb_target_group.notes_app_green.name
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-codedeploy-dg"
      Role = "codedeploy-deployment-group"
    }
  )
}

