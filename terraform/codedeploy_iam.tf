# =============================================================================
# CodeDeploy IAM Role for ECS Blue/Green
# =============================================================================
# Purpose:
#   - Allow AWS CodeDeploy to orchestrate blue/green deployments for the
#     Notes App ECS service (create/shift/terminate task sets via ECS + ALB).
# Notes:
#   - Uses the AWS managed policy AWSCodeDeployRoleForECS, which grants the
#     minimal set of permissions CodeDeploy needs for ECS deployments.
# =============================================================================

resource "aws_iam_role" "codedeploy_ecs" {
  name_prefix = "${var.environment}-codedeploy-ecs-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-codedeploy-ecs-role"
      Role = "codedeploy-service-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs_managed" {
  role       = aws_iam_role.codedeploy_ecs.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

