# =============================================================================
# CloudWatch Alarm for ALB 5xx Errors (CodeDeploy Rollback Trigger)
# =============================================================================
# Purpose:
#   - Monitor HTTP 5xx responses from the Notes App ALB target group and
#     trigger automatic rollback in CodeDeploy when error rate spikes during
#     a deployment.
# Notes:
#   - Wired into aws_codedeploy_deployment_group.notes_app via
#     alarm_configuration and auto_rollback_configuration.
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.environment}-notes-app-5xx-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10

  dimensions = {
    LoadBalancer = aws_lb.notes_app.arn_suffix
    TargetGroup  = aws_lb_target_group.notes_app.arn_suffix
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-5xx-alarm"
      Role = "alb-5xx-alarm"
    }
  )
}

