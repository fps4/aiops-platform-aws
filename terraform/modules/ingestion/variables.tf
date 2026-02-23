variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "aiops"
}

variable "lambda_execution_role_arn" {
  description = "ARN of Lambda execution role"
  type        = string
}

variable "firehose_delivery_role_arn" {
  description = "ARN of Firehose delivery role"
  type        = string
}

variable "raw_logs_bucket_arn" {
  description = "ARN of the raw logs S3 bucket"
  type        = string
}

variable "raw_logs_bucket_name" {
  description = "Name of the raw logs S3 bucket"
  type        = string
}

variable "clickhouse_host" {
  description = "ClickHouse hostname (Cloud Map DNS or IP)"
  type        = string
}

variable "clickhouse_port" {
  description = "ClickHouse HTTP port"
  type        = number
  default     = 8123
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
