# Log subscriptions for GIA Lambda services (same-account)

locals {
  log_groups = [
    "/aws/lambda/mcg-jwt-authorizer",
    "/aws/apigateway/mcg-dev-edge",
    "/aws/lambda/aiops-test-sub",
  ]
}

# Dedicated test log group to validate end-to-end ingestion
resource "aws_cloudwatch_log_group" "aiops_test_sub" {
  name              = "/aws/lambda/aiops-test-sub"
  retention_in_days = 14
}

module "logs_gia" {
  source = "../../modules/log-subscription"

  for_each       = toset(local.log_groups)
  environment    = var.environment
  project_prefix = var.project_prefix
  # Use the last path segment of the log group name for a clean application identifier
  application_name = element(reverse(split("/", each.value)), 0)
  log_group_name   = each.value

  firehose_stream_arn                   = module.ingestion.firehose_stream_arn
  cloudwatch_logs_subscription_role_arn = module.ingestion.cloudwatch_logs_subscription_role_arn
}
