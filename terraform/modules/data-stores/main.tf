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

# Managed OpenSearch domain (single t3.small.search for dev)
resource "aws_opensearch_domain" "logs" {
  domain_name    = "${var.project_prefix}-${var.environment}-logs"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type          = "t3.small.search"
    instance_count         = 1
    zone_awareness_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 20
    volume_type = "gp3"
  }

  encrypt_at_rest { enabled = true }
  node_to_node_encryption { enabled = true }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.central_account_id}:root" }
        Action   = ["es:ESHttp*"]
        Resource = "arn:aws:es:${var.aws_region}:${var.central_account_id}:domain/${var.project_prefix}-${var.environment}-logs/*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# OpenSearch Application (cloud-hosted Dashboards UI with IAM auth)
resource "aws_opensearch_application" "dashboards" {
  name = "${var.project_prefix}-${var.environment}-dashboards"

  data_source {
    data_source_arn         = aws_opensearch_domain.logs.arn
    data_source_description = "AIOps platform OpenSearch domain"
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-dashboards"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
