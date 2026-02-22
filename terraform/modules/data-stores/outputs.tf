output "raw_logs_bucket_name" {
  description = "Name of raw logs S3 bucket"
  value       = aws_s3_bucket.raw_logs.id
}

output "raw_logs_bucket_arn" {
  description = "ARN of raw logs S3 bucket"
  value       = aws_s3_bucket.raw_logs.arn
}

output "audit_logs_bucket_name" {
  description = "Name of audit logs S3 bucket"
  value       = aws_s3_bucket.audit_logs.id
}

output "dashboard_screenshots_bucket_name" {
  description = "Name of dashboard screenshots S3 bucket"
  value       = aws_s3_bucket.dashboard_screenshots.id
}

output "anomalies_table_name" {
  description = "Name of anomalies DynamoDB table"
  value       = aws_dynamodb_table.anomalies.name
}

output "anomalies_table_arn" {
  description = "ARN of anomalies DynamoDB table"
  value       = aws_dynamodb_table.anomalies.arn
}

output "anomalies_table_stream_arn" {
  description = "ARN of anomalies DynamoDB stream"
  value       = aws_dynamodb_table.anomalies.stream_arn
}

output "events_table_name" {
  description = "Name of events DynamoDB table"
  value       = aws_dynamodb_table.events.name
}

output "policy_store_table_name" {
  description = "Name of policy store DynamoDB table"
  value       = aws_dynamodb_table.policy_store.name
}

output "agent_state_table_name" {
  description = "Name of agent state DynamoDB table"
  value       = aws_dynamodb_table.agent_state.name
}

output "opensearch_domain_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.logs.endpoint
}

output "opensearch_domain_arn" {
  description = "ARN of OpenSearch domain"
  value       = aws_opensearch_domain.logs.arn
}
