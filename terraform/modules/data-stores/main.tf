# S3 Buckets

data "aws_caller_identity" "current" {}

locals {
  name_prefix   = "${var.project_prefix}-${var.environment}"
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

# ─── ClickHouse (plain Linux EC2) ─────────────────────────────────────────────

# Derive VPC from the subnet
data "aws_subnet" "clickhouse" {
  count = var.subnet_id != "" ? 1 : 0
  id    = var.subnet_id
}

data "aws_vpc" "clickhouse" {
  count = var.subnet_id != "" ? 1 : 0
  id    = data.aws_subnet.clickhouse[0].vpc_id
}

# Security group: allow ClickHouse HTTP (8123) from within the VPC
resource "aws_security_group" "clickhouse" {
  count       = var.subnet_id != "" ? 1 : 0
  name        = "${local.name_prefix}-clickhouse"
  description = "Allow ClickHouse HTTP access from within VPC"
  vpc_id      = data.aws_subnet.clickhouse[0].vpc_id

  ingress {
    description = "ClickHouse HTTP interface"
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.clickhouse[0].cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-clickhouse"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM role for ClickHouse EC2 (SSM + CloudWatch, no ECS needed)
resource "aws_iam_role" "clickhouse_ec2" {
  count = var.subnet_id != "" ? 1 : 0
  name  = "${local.name_prefix}-clickhouse-ec2"

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

resource "aws_iam_role_policy_attachment" "clickhouse_ec2_ssm" {
  count      = var.subnet_id != "" ? 1 : 0
  role       = aws_iam_role.clickhouse_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "clickhouse_ec2_cloudwatch" {
  count      = var.subnet_id != "" ? 1 : 0
  role       = aws_iam_role.clickhouse_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "clickhouse_ec2" {
  count = var.subnet_id != "" ? 1 : 0
  name  = "${local.name_prefix}-clickhouse-ec2"
  role  = aws_iam_role.clickhouse_ec2[0].name
}

# Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Separate EBS volume for ClickHouse data (100 GB gp3, persists across instance replacements)
resource "aws_ebs_volume" "clickhouse_data" {
  count             = var.subnet_id != "" ? 1 : 0
  availability_zone = data.aws_subnet.clickhouse[0].availability_zone
  size              = 100
  type              = "gp3"

  tags = {
    Name        = "${local.name_prefix}-clickhouse-data"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Plain EC2 instance for ClickHouse (t3.large, AL2023, systemd)
resource "aws_instance" "clickhouse" {
  count                  = var.subnet_id != "" ? 1 : 0
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.large"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.clickhouse[0].id]
  iam_instance_profile   = aws_iam_instance_profile.clickhouse_ec2[0].name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # user_data installs ClickHouse and waits for the data volume to be attached
  # by Terraform (aws_volume_attachment). The wait loop handles the timing gap
  # between instance launch and volume attachment (~1-2 min in practice).
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Add ClickHouse RPM repository
    {
      echo '[clickhouse-stable]'
      echo 'name=ClickHouse - Stable Repository'
      echo 'baseurl=https://packages.clickhouse.com/rpm/stable/'
      echo 'gpgcheck=1'
      echo 'gpgkey=https://packages.clickhouse.com/rpm/stable/repodata/repomd.xml.key'
      echo 'enabled=1'
    } > /etc/yum.repos.d/clickhouse.repo

    dnf install -y clickhouse-server clickhouse-client

    # Configure ClickHouse to listen on all interfaces
    mkdir -p /etc/clickhouse-server/config.d
    {
      echo '<clickhouse>'
      echo '    <listen_host>0.0.0.0</listen_host>'
      echo '</clickhouse>'
    } > /etc/clickhouse-server/config.d/listen.xml

    # Wait for the data volume to be attached by Terraform (up to 5 minutes).
    # On Nitro instances (t3.*), /dev/xvdb is surfaced as /dev/nvme1n1 by the kernel.
    DATA_DEV=""
    i=0
    while [ $i -lt 60 ]; do
      if [ -b /dev/nvme1n1 ]; then
        DATA_DEV=/dev/nvme1n1
        break
      fi
      if [ -b /dev/xvdb ]; then
        DATA_DEV=/dev/xvdb
        break
      fi
      i=$((i + 1))
      sleep 5
    done

    if [ -n "$DATA_DEV" ]; then
      # Format only if not already formatted (idempotent on reboot)
      if ! blkid "$DATA_DEV" > /dev/null 2>&1; then
        mkfs -t xfs "$DATA_DEV"
      fi
      mkdir -p /var/lib/clickhouse
      mount "$DATA_DEV" /var/lib/clickhouse
      echo "$DATA_DEV /var/lib/clickhouse xfs defaults,nofail 0 2" >> /etc/fstab
      chown -R clickhouse:clickhouse /var/lib/clickhouse
    fi

    # Enable and start ClickHouse
    systemctl enable --now clickhouse-server

    # Wait for ClickHouse to be ready (up to 60 seconds)
    i=0
    while [ $i -lt 30 ]; do
      if clickhouse-client -q "SELECT 1" > /dev/null 2>&1; then
        break
      fi
      i=$((i + 1))
      sleep 2
    done

    # Create aiops database
    clickhouse-client -q "CREATE DATABASE IF NOT EXISTS aiops"
  EOF
  )

  tags = {
    Name        = "${local.name_prefix}-clickhouse"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Attach the data volume to the ClickHouse instance
resource "aws_volume_attachment" "clickhouse_data" {
  count       = var.subnet_id != "" ? 1 : 0
  device_name = "/dev/xvdb"
  volume_id   = aws_ebs_volume.clickhouse_data[0].id
  instance_id = aws_instance.clickhouse[0].id
}
