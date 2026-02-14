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

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = aws_opensearchserverless_collection.logs.collection_endpoint
}

output "opensearch_collection_arn" {
  description = "ARN of OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.logs.arn
}

output "opensearch_collection_id" {
  description = "ID of OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.logs.id
}

output "timestream_database_name" {
  description = "Name of Timestream database (empty if disabled)"
  value       = var.enable_timestream ? aws_timestreamwrite_database.metrics[0].database_name : ""
}

output "timestream_table_name" {
  description = "Name of Timestream table (empty if disabled)"
  value       = var.enable_timestream ? aws_timestreamwrite_table.metrics[0].table_name : ""
}
