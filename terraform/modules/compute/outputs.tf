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
  description = "Grafana ALB URL (internal, port 3000)"
  value       = length(aws_lb.grafana) > 0 ? "http://${aws_lb.grafana[0].dns_name}:3000" : ""
}
