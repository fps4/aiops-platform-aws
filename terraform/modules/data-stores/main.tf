# S3 Buckets

data "aws_caller_identity" "current" {}

locals {
  bucket_prefix = "${data.aws_caller_identity.current.account_id}-${var.project_prefix}-${var.environment}"
}

# Raw logs bucket
resource "aws_s3_bucket" "raw_logs" {
  bucket = "${local.bucket_prefix}-raw-logs"

  tags = {
    Name        = "${local.bucket_prefix}-raw-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {} # Apply to all objects

    expiration {
      days = var.retention_days
    }
  }
}

resource "aws_s3_bucket_versioning" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Audit logs bucket
resource "aws_s3_bucket" "audit_logs" {
  bucket = "${local.bucket_prefix}-audit-logs"

  tags = {
    Name        = "${local.bucket_prefix}-audit-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "expire-old-audits"
    status = "Enabled"

    filter {} # Apply to all objects

    expiration {
      days = 365 # Keep audit logs for 1 year
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Dashboard screenshots bucket
resource "aws_s3_bucket" "dashboard_screenshots" {
  bucket = "${local.bucket_prefix}-dashboard-screenshots"

  tags = {
    Name        = "${local.bucket_prefix}-dashboard-screenshots"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "dashboard_screenshots" {
  bucket = aws_s3_bucket.dashboard_screenshots.id

  rule {
    id     = "expire-old-screenshots"
    status = "Enabled"

    filter {} # Apply to all objects

    expiration {
      days = 1 # Screenshots expire after 24 hours
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dashboard_screenshots" {
  bucket = aws_s3_bucket.dashboard_screenshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB Tables
# NOTE: hash_key/range_key are deprecated in AWS provider v6 in favor of key_schema blocks,
# but key_schema is not yet implemented as of v6.33. Migrate when the provider adds support.

# Anomalies table
resource "aws_dynamodb_table" "anomalies" {
  name             = "${var.project_prefix}-${var.environment}-anomalies"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "anomaly_id"
  range_key        = "timestamp"
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  attribute {
    name = "anomaly_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "account_id"
    type = "S"
  }

  attribute {
    name = "service"
    type = "S"
  }

  global_secondary_index {
    name            = "AccountServiceIndex"
    hash_key        = "account_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "ServiceIndex"
    hash_key        = "service"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-anomalies"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Events table
resource "aws_dynamodb_table" "events" {
  name         = "${var.project_prefix}-${var.environment}-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_key"
  range_key    = "timestamp"

  attribute {
    name = "event_key"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "event_type"
    type = "S"
  }

  global_secondary_index {
    name            = "EventTypeIndex"
    hash_key        = "event_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-events"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Policy store table
resource "aws_dynamodb_table" "policy_store" {
  name         = "${var.project_prefix}-${var.environment}-policy-store"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "policy_id"

  attribute {
    name = "policy_id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-policy-store"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Agent state table
resource "aws_dynamodb_table" "agent_state" {
  name         = "${var.project_prefix}-${var.environment}-agent-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "workflow_id"
  range_key    = "step_name"

  attribute {
    name = "workflow_id"
    type = "S"
  }

  attribute {
    name = "step_name"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-agent-state"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Audit logs table (for AI provider calls tracking)
resource "aws_dynamodb_table" "audit_logs" {
  name         = "${var.project_prefix}-${var.environment}-audit-logs-index"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"
  range_key    = "timestamp"

  attribute {
    name = "request_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "agent_type"
    type = "S"
  }

  global_secondary_index {
    name            = "AgentTypeIndex"
    hash_key        = "agent_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-audit-logs-index"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── ClickHouse (ECS EC2) ─────────────────────────────────────────────────────

# Derive VPC from first subnet when subnets are supplied
data "aws_subnet" "clickhouse_primary" {
  count = length(var.subnet_ids) > 0 ? 1 : 0
  id    = var.subnet_ids[0]
}

# Security group: allow ClickHouse HTTP (8123) from within the VPC
resource "aws_security_group" "clickhouse" {
  count       = length(var.subnet_ids) > 0 ? 1 : 0
  name        = "${local.bucket_prefix}-clickhouse"
  description = "Allow ClickHouse HTTP access from within VPC"
  vpc_id      = data.aws_subnet.clickhouse_primary[0].vpc_id

  ingress {
    description = "ClickHouse HTTP interface"
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = [data.aws_subnet.clickhouse_primary[0].cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.bucket_prefix}-clickhouse"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM role and instance profile for ECS EC2 nodes
resource "aws_iam_role" "clickhouse_ec2" {
  count = length(var.subnet_ids) > 0 ? 1 : 0
  name  = "${local.bucket_prefix}-clickhouse-ec2"

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

resource "aws_iam_role_policy_attachment" "clickhouse_ec2_ecs" {
  count      = length(var.subnet_ids) > 0 ? 1 : 0
  role       = aws_iam_role.clickhouse_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "clickhouse_ec2" {
  count = length(var.subnet_ids) > 0 ? 1 : 0
  name  = "${local.bucket_prefix}-clickhouse-ec2"
  role  = aws_iam_role.clickhouse_ec2[0].name
}

# ECS-optimised Amazon Linux 2 AMI
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# EC2 Launch Template for ClickHouse
resource "aws_launch_template" "clickhouse" {
  count         = length(var.subnet_ids) > 0 ? 1 : 0
  name_prefix   = "${local.bucket_prefix}-clickhouse-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.large"

  iam_instance_profile {
    arn = aws_iam_instance_profile.clickhouse_ec2[0].arn
  }

  vpc_security_group_ids = [aws_security_group.clickhouse[0].id]

  # EBS root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
    }
  }

  # Extra EBS volume for ClickHouse data
  block_device_mappings {
    device_name = "/dev/xvdb"
    ebs {
      volume_size = 100
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${local.bucket_prefix}-clickhouse >> /etc/ecs/ecs.config
    mkfs -t xfs /dev/xvdb
    mkdir -p /var/lib/clickhouse
    mount /dev/xvdb /var/lib/clickhouse
    echo '/dev/xvdb /var/lib/clickhouse xfs defaults,nofail 0 2' >> /etc/fstab
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.bucket_prefix}-clickhouse"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Auto Scaling Group (single instance for dev)
resource "aws_autoscaling_group" "clickhouse" {
  count               = length(var.subnet_ids) > 0 ? 1 : 0
  name                = "${local.bucket_prefix}-clickhouse"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 1
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.clickhouse[0].id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ECS Cluster for ClickHouse
resource "aws_ecs_cluster" "clickhouse" {
  count = length(var.subnet_ids) > 0 ? 1 : 0
  name  = "${local.bucket_prefix}-clickhouse"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Environment = var.environment, ManagedBy = "terraform" }
}

# ECS Capacity Provider backed by the ASG
resource "aws_ecs_capacity_provider" "clickhouse_ec2" {
  count = length(var.subnet_ids) > 0 ? 1 : 0
  name  = "${local.bucket_prefix}-clickhouse-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.clickhouse[0].arn

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "clickhouse" {
  count              = length(var.subnet_ids) > 0 ? 1 : 0
  cluster_name       = aws_ecs_cluster.clickhouse[0].name
  capacity_providers = [aws_ecs_capacity_provider.clickhouse_ec2[0].name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.clickhouse_ec2[0].name
    weight            = 1
  }
}

# Cloud Map for stable service-discovery DNS
resource "aws_service_discovery_private_dns_namespace" "aiops" {
  count = length(var.subnet_ids) > 0 ? 1 : 0
  name  = "${var.project_prefix}-${var.environment}.local"
  vpc   = data.aws_subnet.clickhouse_primary[0].vpc_id

  tags = { Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_service_discovery_service" "clickhouse" {
  count = length(var.subnet_ids) > 0 ? 1 : 0
  name  = "clickhouse"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.aiops[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# CloudWatch log group for ClickHouse ECS task
resource "aws_cloudwatch_log_group" "clickhouse" {
  count             = length(var.subnet_ids) > 0 ? 1 : 0
  name              = "/ecs/${local.bucket_prefix}-clickhouse"
  retention_in_days = 14

  tags = { Environment = var.environment, ManagedBy = "terraform" }
}

# ECS Task Definition for ClickHouse (host networking for direct port access)
resource "aws_ecs_task_definition" "clickhouse" {
  count                 = length(var.subnet_ids) > 0 ? 1 : 0
  family                = "${local.bucket_prefix}-clickhouse"
  requires_compatibilities = ["EC2"]
  network_mode          = "host"

  container_definitions = jsonencode([
    {
      name      = "clickhouse"
      image     = "clickhouse/clickhouse-server:latest"
      essential = true

      portMappings = [
        { containerPort = 8123, hostPort = 8123, protocol = "tcp" },
        { containerPort = 9000, hostPort = 9000, protocol = "tcp" }
      ]

      mountPoints = [
        { sourceVolume = "clickhouse-data", containerPath = "/var/lib/clickhouse" }
      ]

      environment = [
        { name = "CLICKHOUSE_DB", value = "aiops" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.clickhouse[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  volume {
    name      = "clickhouse-data"
    host_path = "/var/lib/clickhouse"
  }

  tags = { Environment = var.environment, ManagedBy = "terraform" }
}

# ECS Service for ClickHouse with Cloud Map service discovery
resource "aws_ecs_service" "clickhouse" {
  count           = length(var.subnet_ids) > 0 ? 1 : 0
  name            = "${local.bucket_prefix}-clickhouse"
  cluster         = aws_ecs_cluster.clickhouse[0].id
  task_definition = aws_ecs_task_definition.clickhouse[0].arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.clickhouse_ec2[0].name
    weight            = 1
  }

  service_registries {
    registry_arn = aws_service_discovery_service.clickhouse[0].arn
  }

  depends_on = [aws_ecs_cluster_capacity_providers.clickhouse]

  tags = { Environment = var.environment, ManagedBy = "terraform" }
}
