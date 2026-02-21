output "firehose_stream_arn" {
  description = "ARN of the Kinesis Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.log_stream.arn
}

output "firehose_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.log_stream.name
}

output "log_normalizer_function_arn" {
  description = "ARN of the log-normalizer Lambda function"
  value       = aws_lambda_function.log_normalizer.arn
}

output "log_normalizer_function_name" {
  description = "Name of the log-normalizer Lambda function"
  value       = aws_lambda_function.log_normalizer.function_name
}

output "cloudwatch_logs_destination_arn" {
  description = "ARN of the CloudWatch Logs destination"
  value       = aws_cloudwatch_log_destination.logs_destination.arn
}

output "cloudwatch_logs_subscription_role_arn" {
  description = "ARN of the IAM role CloudWatch Logs assumes to write to Firehose (use as role_arn in subscription filters)"
  value       = aws_iam_role.cloudwatch_logs_subscription.arn
}
