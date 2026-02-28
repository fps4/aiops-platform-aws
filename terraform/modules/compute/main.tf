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

# ─── Networking Helpers ───────────────────────────────────────────────────────

# Derive VPC for the provided Fargate subnets (only when subnets are given).
data "aws_subnet" "fargate_primary" {
  count = length(var.fargate_subnet_ids) > 0 ? 1 : 0

  id = var.fargate_subnet_ids[0]
}

# Security group with allow-all egress for Fargate tasks when no SGs are supplied.
resource "aws_security_group" "fargate_egress_all" {
  count = length(var.fargate_subnet_ids) > 0 ? 1 : 0

  name        = "${local.name_prefix}-fargate-egress"
  description = "Allow all egress for Fargate tasks"
  vpc_id      = data.aws_subnet.fargate_primary[0].vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
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
        { name = "CLICKHOUSE_HOST",          value = var.clickhouse_host },
        { name = "CLICKHOUSE_PORT",          value = tostring(var.clickhouse_port) },
        { name = "DYNAMODB_ANOMALIES_TABLE", value = var.anomalies_table_name },
        { name = "DYNAMODB_POLICY_TABLE",    value = var.policy_store_table_name },
        { name = "ENVIRONMENT",              value = var.environment },
        { name = "AWS_REGION",               value = var.aws_region },
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
        security_groups  = length(var.fargate_security_group_ids) > 0 ? var.fargate_security_group_ids : [aws_security_group.fargate_egress_all[0].id]
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
      CLICKHOUSE_HOST          = var.clickhouse_host
      CLICKHOUSE_PORT          = tostring(var.clickhouse_port)
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
      CLICKHOUSE_HOST            = var.clickhouse_host
      CLICKHOUSE_PORT            = tostring(var.clickhouse_port)
      GRAFANA_URL                = length(aws_instance.grafana) > 0 ? "http://${aws_instance.grafana[0].private_ip}:3000" : ""
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

# ─── Grafana (plain Linux EC2, AL2023, systemd) ───────────────────────────────

# Derive VPC for Grafana security group
data "aws_subnet" "grafana_ec2" {
  count = var.ec2_subnet_id != "" ? 1 : 0
  id    = var.ec2_subnet_id
}

data "aws_vpc" "grafana" {
  count = var.ec2_subnet_id != "" ? 1 : 0
  id    = data.aws_subnet.grafana_ec2[0].vpc_id
}

# Amazon Linux 2023 AMI (same pattern as ClickHouse)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# IAM role for Grafana EC2 (SSM access — no SSH keys needed)
resource "aws_iam_role" "grafana_ec2" {
  count = var.ec2_subnet_id != "" ? 1 : 0
  name  = "${local.name_prefix}-grafana-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_iam_role_policy_attachment" "grafana_ec2_ssm" {
  count      = var.ec2_subnet_id != "" ? 1 : 0
  role       = aws_iam_role.grafana_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "grafana_ec2_cloudwatch" {
  count      = var.ec2_subnet_id != "" ? 1 : 0
  role       = aws_iam_role.grafana_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "grafana_ec2" {
  count = var.ec2_subnet_id != "" ? 1 : 0
  name  = "${local.name_prefix}-grafana-ec2"
  role  = aws_iam_role.grafana_ec2[0].name
}

# Security group: port 3000 from VPC CIDR only
resource "aws_security_group" "grafana" {
  count       = var.ec2_subnet_id != "" ? 1 : 0
  name        = "${local.name_prefix}-grafana"
  description = "Allow Grafana access from within VPC"
  vpc_id      = data.aws_subnet.grafana_ec2[0].vpc_id

  ingress {
    description = "Grafana HTTP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.grafana[0].cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Plain EC2 instance for Grafana (t3.small — ~500 MB RAM needed)
resource "aws_instance" "grafana" {
  count                  = var.ec2_subnet_id != "" ? 1 : 0
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  subnet_id              = var.ec2_subnet_id
  vpc_security_group_ids = [aws_security_group.grafana[0].id]
  iam_instance_profile   = aws_iam_instance_profile.grafana_ec2[0].name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Add Grafana RPM repository
    {
      echo '[grafana]'
      echo 'name=grafana'
      echo 'baseurl=https://rpm.grafana.com'
      echo 'repo_gpgcheck=1'
      echo 'enabled=1'
      echo 'gpgcheck=1'
      echo 'gpgkey=https://rpm.grafana.com/gpg.key'
      echo 'sslverify=1'
      echo 'sslcacert=/etc/pki/tls/certs/ca-bundle.crt'
    } > /etc/yum.repos.d/grafana.repo

    dnf install -y grafana

    # Install ClickHouse datasource plugin
    grafana-cli plugins install grafana-clickhouse-datasource

    # Enable and start Grafana
    systemctl enable --now grafana-server
  EOF
  )

  tags = {
    Name        = "${local.name_prefix}-grafana"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
