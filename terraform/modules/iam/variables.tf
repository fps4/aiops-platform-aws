# IAM Module - Cross-account roles and Lambda execution roles

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "central_account_id" {
  description = "AWS account ID for central observability account"
  type        = string
}

variable "member_account_ids" {
  description = "List of member AWS account IDs"
  type        = list(string)
  default     = []
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "aiops"
}
