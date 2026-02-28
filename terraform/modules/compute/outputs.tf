output "ecs_cluster_arn" {
  description = "ARN of the ECS detection cluster"
  value       = aws_ecs_cluster.detection.arn
}

output "detection_task_definition_arn" {
  description = "ARN of the statistical detection ECS task definition"
  value       = aws_ecs_task_definition.statistical_detection.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for the statistical detection image"
  value       = aws_ecr_repository.statistical_detection.repository_url
}

output "rule_detection_function_arn" {
  description = "ARN of the rule-based detection Lambda function"
  value       = aws_lambda_function.rule_detection.arn
}

output "rule_detection_function_name" {
  description = "Name of the rule-based detection Lambda function"
  value       = aws_lambda_function.rule_detection.function_name
}

output "orchestrator_function_arn" {
  description = "ARN of the orchestrator Lambda function"
  value       = aws_lambda_function.orchestrator.arn
}

output "orchestrator_function_name" {
  description = "Name of the orchestrator Lambda function"
  value       = aws_lambda_function.orchestrator.function_name
}

output "grafana_url" {
  description = "Grafana URL (EC2 private IP, port 3000)"
  value       = length(aws_instance.grafana) > 0 ? "http://${aws_instance.grafana[0].private_ip}:3000" : ""
}

output "grafana_instance_id" {
  description = "Grafana EC2 instance ID (for SSM port forwarding)"
  value       = length(aws_instance.grafana) > 0 ? aws_instance.grafana[0].id : ""
}
