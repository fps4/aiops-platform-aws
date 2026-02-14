output "lambda_execution_role_arn" {
  description = "ARN of Lambda execution role"
  value       = module.iam.lambda_execution_role_arn
}

output "step_functions_execution_role_arn" {
  description = "ARN of Step Functions execution role"
  value       = module.iam.step_functions_execution_role_arn
}

output "raw_logs_bucket_name" {
  description = "Name of raw logs S3 bucket"
  value       = module.data_stores.raw_logs_bucket_name
}

output "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = module.data_stores.opensearch_collection_endpoint
}

output "anomalies_table_name" {
  description = "Name of anomalies DynamoDB table"
  value       = module.data_stores.anomalies_table_name
}

output "anomalies_stream_arn" {
  description = "ARN of anomalies DynamoDB stream"
  value       = module.data_stores.anomalies_table_stream_arn
}

output "timestream_database" {
  description = "Timestream database name"
  value       = module.data_stores.timestream_database_name
}

output "timestream_table" {
  description = "Timestream table name"
  value       = module.data_stores.timestream_table_name
}

output "slack_webhook_secret_arn" {
  description = "ARN of Slack webhook secret"
  value       = aws_secretsmanager_secret.slack_webhook.arn
}
