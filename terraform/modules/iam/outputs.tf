output "lambda_execution_role_arn" {
  description = "ARN of Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "step_functions_execution_role_arn" {
  description = "ARN of Step Functions execution role"
  value       = aws_iam_role.step_functions_execution.arn
}

output "firehose_delivery_role_arn" {
  description = "ARN of Firehose delivery role"
  value       = aws_iam_role.firehose_delivery.arn
}

output "cross_account_read_role_arn" {
  description = "ARN of cross-account read role (empty if no member accounts configured)"
  value       = length(var.member_account_ids) > 0 ? aws_iam_role.cross_account_read[0].arn : ""
}
