variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "aiops"
}

variable "application_name" {
  description = "Short name for the application (used in the subscription filter name)"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group to subscribe (e.g. /aws/lambda/my-function)"
  type        = string
}

variable "filter_pattern" {
  description = "CloudWatch Logs filter pattern. Empty string forwards all log events."
  type        = string
  default     = ""
}

variable "firehose_stream_arn" {
  description = "ARN of the Kinesis Firehose delivery stream"
  type        = string
}

variable "cloudwatch_logs_subscription_role_arn" {
  description = "ARN of the IAM role CloudWatch Logs assumes to write to Firehose"
  type        = string
}
