output "lambda_execution_role_arn" {
  description = "ARN of Lambda execution role"
  value       = module.iam.lambda_execution_role_arn
}

output "fargate_task_role_arn" {
  description = "ARN of Fargate task role"
  value       = module.iam.fargate_task_role_arn
}

output "raw_logs_bucket_name" {
  description = "Name of raw logs S3 bucket"
  value       = module.data_stores.raw_logs_bucket_name
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = module.data_stores.opensearch_domain_endpoint
}

output "anomalies_table_name" {
  description = "Name of anomalies DynamoDB table"
  value       = module.data_stores.anomalies_table_name
}

output "anomalies_stream_arn" {
  description = "ARN of anomalies DynamoDB stream"
  value       = module.data_stores.anomalies_table_stream_arn
}

output "firehose_stream_arn" {
  description = "ARN of Kinesis Firehose delivery stream"
  value       = module.ingestion.firehose_stream_arn
}

output "log_normalizer_function_name" {
  description = "Name of log normalizer Lambda function"
  value       = module.ingestion.log_normalizer_function_arn
}

output "cloudwatch_logs_destination_arn" {
  description = "ARN of the CloudWatch Logs destination (use in cross-account subscription filters)"
  value       = module.ingestion.cloudwatch_logs_destination_arn
}

output "cloudwatch_logs_subscription_role_arn" {
  description = "ARN of the IAM role for same-account CloudWatch Logs subscription filters"
  value       = module.ingestion.cloudwatch_logs_subscription_role_arn
}

output "slack_webhook_secret_arn" {
  description = "ARN of Slack webhook secret"
  value       = aws_secretsmanager_secret.slack_webhook.arn
}

output "orchestrator_function_name" {
  description = "Name of the orchestrator Lambda function"
  value       = module.compute.orchestrator_function_name
}

output "orchestrator_function_arn" {
  description = "ARN of the orchestrator Lambda function"
  value       = module.compute.orchestrator_function_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for statistical detection image"
  value       = module.compute.ecr_repository_url
}
