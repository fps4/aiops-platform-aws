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

output "clickhouse_instance_id" {
  description = "ClickHouse EC2 instance ID (for SSM port forwarding)"
  value       = length(aws_instance.clickhouse) > 0 ? aws_instance.clickhouse[0].id : ""
}

output "clickhouse_host" {
  description = "ClickHouse EC2 private IP address"
  value       = length(aws_instance.clickhouse) > 0 ? aws_instance.clickhouse[0].private_ip : ""
}

output "clickhouse_port" {
  description = "ClickHouse HTTP port"
  value       = "8123"
}

output "clickhouse_security_group_id" {
  description = "ID of the ClickHouse security group"
  value       = length(aws_security_group.clickhouse) > 0 ? aws_security_group.clickhouse[0].id : ""
}
