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

variable "fargate_task_role_arn" {
  description = "ARN of Fargate task role"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of ECS task execution role"
  type        = string
}

variable "opensearch_endpoint" {
  description = "OpenSearch endpoint"
  type        = string
}

variable "opensearch_service" {
  description = "OpenSearch SigV4 service name (es or aoss)"
  type        = string
  default     = "es"
}

variable "anomalies_table_name" {
  description = "Name of the DynamoDB anomalies table"
  type        = string
}

variable "policy_store_table_name" {
  description = "Name of the DynamoDB policy store table"
  type        = string
}

variable "events_table_name" {
  description = "Name of the DynamoDB events table"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "fargate_subnet_ids" {
  description = "Subnet IDs for the Fargate statistical detection task. When empty the EventBridge schedule is not created."
  type        = list(string)
  default     = []
}

variable "fargate_security_group_ids" {
  description = "Security group IDs to attach to the Fargate task network interface. Defaults to empty (uses VPC default SG)."
  type        = list(string)
  default     = []
}

variable "anomalies_table_stream_arn" {
  description = "ARN of the DynamoDB Streams stream on the anomalies table (triggers orchestrator Lambda)"
  type        = string
}

variable "agent_state_table_name" {
  description = "Name of the DynamoDB agent_state table used by the orchestrator"
  type        = string
}

variable "slack_webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Slack webhook URL"
  type        = string
}
