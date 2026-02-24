 # =============================================================================
 # ECS Task Roles (Execution + Task Role)
 # =============================================================================
 # Purpose:
 #   - Task execution role: pull images from ECR, write logs to CloudWatch Logs,
 #     read secrets/parameters if needed.
 #   - Task role: runtime permissions for the application containers (none needed
 #     yet; defined for future extension).
 # =============================================================================

 data "aws_iam_policy_document" "ecs_task_execution_assume_role" {
   statement {
     effect = "Allow"

     principals {
       type        = "Service"
       identifiers = ["ecs-tasks.amazonaws.com"]
     }

     actions = ["sts:AssumeRole"]
   }
 }

 resource "aws_iam_role" "ecs_task_execution" {
   name_prefix        = "${var.environment}-notes-app-ecs-task-execution-"
   assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json
   description        = "Execution role for Notes App ECS tasks (Fargate)"

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-app-ecs-task-execution-role"
     }
   )
 }

 # AWS managed policy: pull images from ECR, write logs to CloudWatch Logs, etc.
 resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
   role       = aws_iam_role.ecs_task_execution.name
   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
 }

 # Additional CloudWatch Logs permissions (mirror EC2 pattern, but scoped to ECS)
 resource "aws_iam_role_policy" "ecs_task_execution_logs" {
   name = "ecs-task-execution-cloudwatch-logs"
   role = aws_iam_role.ecs_task_execution.id

   policy = jsonencode({
     Version = "2012-10-17"
     Statement = [
       {
         Sid    = "EcsTaskAwslogsDriver"
         Effect = "Allow"
         Action = [
           "logs:CreateLogGroup",
           "logs:CreateLogStream",
           "logs:PutLogEvents",
           "logs:DescribeLogStreams",
           "logs:DescribeLogGroups"
         ]
         Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/notes-app/ecs/*"
       }
     ]
   })
 }

 # Runtime task role (no permissions yet; containers run with this role's identity)
 data "aws_iam_policy_document" "ecs_task_assume_role" {
   statement {
     effect = "Allow"

     principals {
       type        = "Service"
       identifiers = ["ecs-tasks.amazonaws.com"]
     }

     actions = ["sts:AssumeRole"]
   }
 }

 resource "aws_iam_role" "ecs_task" {
   name_prefix        = "${var.environment}-notes-app-ecs-task-"
   assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
   description        = "Task role for Notes App ECS tasks (application containers)"

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-app-ecs-task-role"
     }
   )
 }

