locals {
  name_prefix = "${var.project_prefix}-${var.environment}"
  # Staging dirs populated by `make build-lambdas` (source + shared + pip deps).
  # Run `make build-lambdas` before terraform apply.
  rule_detection_pkg = "${path.module}/.builds/rule-detection-pkg"
  orchestrator_pkg   = "${path.module}/.builds/orchestrator-pkg"
}

# ─── ECR Repository for Statistical Detection ─────────────────────────────────

resource "aws_ecr_repository" "statistical_detection" {
  name                 = "${local.name_prefix}-statistical-detection"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "statistical_detection" {
  repository = aws_ecr_repository.statistical_detection.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─── ECS Cluster ──────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "detection" {
  name = "${local.name_prefix}-detection-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── CloudWatch Log Group for ECS ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "statistical_detection" {
  name              = "/ecs/${local.name_prefix}-statistical-detection"
  retention_in_days = 14

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── ECS Task Definition ──────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "statistical_detection" {
  family                   = "${local.name_prefix}-statistical-detection"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  task_role_arn            = var.fargate_task_role_arn
  execution_role_arn       = var.ecs_task_execution_role_arn

  container_definitions = jsonencode([
    {
      name  = "statistical-detection"
      image = "${aws_ecr_repository.statistical_detection.repository_url}:latest"

      environment = [
        { name = "OPENSEARCH_ENDPOINT", value = var.opensearch_endpoint },
        { name = "DYNAMODB_ANOMALIES_TABLE", value = var.anomalies_table_name },
        { name = "DYNAMODB_POLICY_TABLE", value = var.policy_store_table_name },
        { name = "ENVIRONMENT", value = var.environment },
        { name = "AWS_REGION", value = var.aws_region },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.statistical_detection.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    }
  ])

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── EventBridge Scheduler for Statistical Detection ──────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "scheduler" {
  name = "${local.name_prefix}-detection-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "scheduler_policy" {
  name = "${local.name_prefix}-detection-scheduler-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RunECSTask"
        Effect = "Allow"
        Action = ["ecs:RunTask"]
        Resource = [
          aws_ecs_task_definition.statistical_detection.arn
        ]
      },
      {
        Sid    = "PassRoles"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          var.fargate_task_role_arn,
          var.ecs_task_execution_role_arn,
        ]
      },
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.rule_detection.arn
        ]
      }
    ]
  })
}

# EventBridge Scheduler is only created when subnet IDs are supplied.
# Set fargate_subnet_ids in your tfvars to enable the schedule.
resource "aws_scheduler_schedule" "statistical_detection" {
  count = length(var.fargate_subnet_ids) > 0 ? 1 : 0

  name = "${local.name_prefix}-statistical-detection-schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(5 minutes)"

  target {
    arn      = aws_ecs_cluster.detection.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.statistical_detection.arn
      launch_type         = "FARGATE"

      network_configuration {
        assign_public_ip = true
        subnets          = var.fargate_subnet_ids
        security_groups  = length(var.fargate_security_group_ids) > 0 ? var.fargate_security_group_ids : null
      }
    }
  }
}

# ─── Rule-Based Detection Lambda ──────────────────────────────────────────────

data "archive_file" "rule_detection" {
  type        = "zip"
  source_dir  = local.rule_detection_pkg
  output_path = "${path.module}/.builds/rule-detection.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_lambda_function" "rule_detection" {
  function_name = "${local.name_prefix}-rule-detection"
  role          = var.lambda_execution_role_arn
  runtime       = "python3.13"
  handler       = "handler.lambda_handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.rule_detection.output_path
  source_code_hash = data.archive_file.rule_detection.output_base64sha256

  environment {
    variables = {
      DYNAMODB_ANOMALIES_TABLE = var.anomalies_table_name
      DYNAMODB_EVENTS_TABLE    = var.events_table_name
      DYNAMODB_POLICY_TABLE    = var.policy_store_table_name
      OPENSEARCH_ENDPOINT      = var.opensearch_endpoint
      ENVIRONMENT              = var.environment
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_scheduler_schedule" "rule_detection" {
  name = "${local.name_prefix}-rule-detection-schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(5 minutes)"

  target {
    arn      = aws_lambda_function.rule_detection.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}

# ─── Orchestrator Lambda ───────────────────────────────────────────────────────

data "archive_file" "orchestrator" {
  type        = "zip"
  source_dir  = local.orchestrator_pkg
  output_path = "${path.module}/.builds/orchestrator.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${local.name_prefix}-orchestrator"
  retention_in_days = 14

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_lambda_function" "orchestrator" {
  function_name = "${local.name_prefix}-orchestrator"
  role          = var.lambda_execution_role_arn
  runtime       = "python3.13"
  handler       = "handler.lambda_handler"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.orchestrator.output_path
  source_code_hash = data.archive_file.orchestrator.output_base64sha256

  environment {
    variables = {
      DYNAMODB_ANOMALIES_TABLE   = var.anomalies_table_name
      DYNAMODB_AGENT_STATE_TABLE = var.agent_state_table_name
      DYNAMODB_EVENTS_TABLE      = var.events_table_name
      OPENSEARCH_ENDPOINT        = var.opensearch_endpoint
      SLACK_WEBHOOK_SECRET_ARN   = var.slack_webhook_secret_arn
      ENVIRONMENT                = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.orchestrator]

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# DynamoDB Streams → Orchestrator Lambda trigger
resource "aws_lambda_event_source_mapping" "anomalies_stream" {
  event_source_arn               = var.anomalies_table_stream_arn
  function_name                  = aws_lambda_function.orchestrator.arn
  starting_position              = "LATEST"
  batch_size                     = 10
  bisect_batch_on_function_error = true

  filter_criteria {
    filter {
      pattern = jsonencode({ eventName = ["INSERT"] })
    }
  }
}
