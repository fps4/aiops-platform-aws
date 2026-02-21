# IAM Module
module "iam" {
  source = "../../modules/iam"

  environment        = var.environment
  project_prefix     = var.project_prefix
  central_account_id = var.central_account_id
  member_account_ids = var.member_account_ids
}

# Data Stores Module
module "data_stores" {
  source = "../../modules/data-stores"

  environment        = var.environment
  project_prefix     = var.project_prefix
  central_account_id = var.central_account_id
  retention_days     = var.retention_days
}

# Ingestion Module
module "ingestion" {
  source = "../../modules/ingestion"

  environment                = var.environment
  project_prefix             = var.project_prefix
  lambda_execution_role_arn  = module.iam.lambda_execution_role_arn
  firehose_delivery_role_arn = module.iam.firehose_delivery_role_arn
  raw_logs_bucket_arn        = module.data_stores.raw_logs_bucket_arn
  raw_logs_bucket_name       = module.data_stores.raw_logs_bucket_name
  opensearch_endpoint        = module.data_stores.opensearch_collection_endpoint
  aws_region                 = var.aws_region
}

# Compute Module
module "compute" {
  source = "../../modules/compute"

  environment                 = var.environment
  project_prefix              = var.project_prefix
  lambda_execution_role_arn   = module.iam.lambda_execution_role_arn
  fargate_task_role_arn       = module.iam.fargate_task_role_arn
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  opensearch_endpoint         = module.data_stores.opensearch_collection_endpoint
  anomalies_table_name        = module.data_stores.anomalies_table_name
  policy_store_table_name     = module.data_stores.policy_store_table_name
  events_table_name           = module.data_stores.events_table_name
  aws_region                  = var.aws_region
  fargate_subnet_ids          = var.fargate_subnet_ids
}

# Secrets Manager - Slack Webhook (placeholder)
resource "aws_secretsmanager_secret" "slack_webhook" {
  name        = "${var.project_prefix}/${var.environment}/slack-webhook"
  description = "Slack webhook URL for AIOps alerts"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "slack_webhook" {
  secret_id = aws_secretsmanager_secret.slack_webhook.id
  secret_string = jsonencode({
    webhook_url = "https://hooks.slack.com/services/PLACEHOLDER/UPDATE/THIS"
  })
}

# SSM Parameter Store - Configuration
resource "aws_ssm_parameter" "region" {
  name  = "/${var.project_prefix}/${var.environment}/region"
  type  = "String"
  value = var.aws_region

  tags = var.tags
}

resource "aws_ssm_parameter" "retention_days" {
  name  = "/${var.project_prefix}/${var.environment}/retention_days"
  type  = "String"
  value = tostring(var.retention_days)

  tags = var.tags
}

resource "aws_ssm_parameter" "sensitivity_default" {
  name        = "/${var.project_prefix}/${var.environment}/sensitivity_default"
  type        = "String"
  value       = "medium"
  description = "Default anomaly detection sensitivity (low, medium, high)"

  tags = var.tags
}

resource "aws_ssm_parameter" "opensearch_endpoint" {
  name  = "/${var.project_prefix}/${var.environment}/opensearch_endpoint"
  type  = "String"
  value = module.data_stores.opensearch_collection_endpoint

  tags = var.tags
}

# Bedrock Configuration - AI Provider Settings
resource "aws_ssm_parameter" "bedrock_rca_model" {
  name        = "/${var.project_prefix}/${var.environment}/bedrock/rca_model_id"
  type        = "String"
  value       = "anthropic.claude-sonnet-4-5-20250929-v1:0"
  description = "Bedrock model ID for RCA agent (requires reasoning)"

  tags = var.tags
}

resource "aws_ssm_parameter" "bedrock_correlation_model" {
  name        = "/${var.project_prefix}/${var.environment}/bedrock/correlation_model_id"
  type        = "String"
  value       = "anthropic.claude-haiku-4-5-20251001-v1:0"
  description = "Bedrock model ID for correlation agent (fast analysis)"

  tags = var.tags
}

resource "aws_ssm_parameter" "bedrock_remediation_model" {
  name        = "/${var.project_prefix}/${var.environment}/bedrock/remediation_model_id"
  type        = "String"
  value       = "anthropic.claude-sonnet-4-5-20250929-v1:0"
  description = "Bedrock model ID for remediation agent"

  tags = var.tags
}

resource "aws_ssm_parameter" "bedrock_region" {
  name        = "/${var.project_prefix}/${var.environment}/bedrock/region"
  type        = "String"
  value       = var.aws_region
  description = "AWS region for Bedrock API calls"

  tags = var.tags
}

resource "aws_ssm_parameter" "bedrock_max_tokens" {
  name        = "/${var.project_prefix}/${var.environment}/bedrock/max_tokens"
  type        = "String"
  value       = "4096"
  description = "Maximum tokens for Bedrock responses"

  tags = var.tags
}

resource "aws_ssm_parameter" "bedrock_rca_temperature" {
  name        = "/${var.project_prefix}/${var.environment}/bedrock/rca_temperature"
  type        = "String"
  value       = "0.2"
  description = "Temperature for RCA agent (deterministic)"

  tags = var.tags
}

resource "aws_ssm_parameter" "bedrock_recommendation_temperature" {
  name        = "/${var.project_prefix}/${var.environment}/bedrock/recommendation_temperature"
  type        = "String"
  value       = "0.3"
  description = "Temperature for recommendation agent"

  tags = var.tags
}
