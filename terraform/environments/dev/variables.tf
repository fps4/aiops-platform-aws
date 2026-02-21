variable "central_account_id" {
  description = "AWS account ID for central observability account"
  type        = string
}

variable "member_account_ids" {
  description = "List of member AWS account IDs"
  type        = list(string)
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-central-1"
}

variable "retention_days" {
  description = "Default retention period in days"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "fargate_subnet_ids" {
  description = "Subnet IDs for Fargate. Defaults to default VPC subnets when empty."
  type        = list(string)
  default     = []
}
