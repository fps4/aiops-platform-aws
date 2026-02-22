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

variable "opensearch_endpoint" {
  description = "OpenSearch endpoint"
  type        = string
}

variable "opensearch_service" {
  description = "OpenSearch SigV4 service name"
  type        = string
  default     = "es"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
