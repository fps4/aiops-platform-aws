# Data Stores Module - S3, DynamoDB, OpenSearch Serverless

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "aiops"
}

variable "retention_days" {
  description = "Default retention period in days"
  type        = number
  default     = 30
}

variable "central_account_id" {
  description = "AWS account ID for central observability account"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-central-1"
}
