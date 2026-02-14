#!/bin/bash

# Get AIOps Platform Configuration from AWS
# Fetches SSM parameters and resource ARNs for local development

set -e

ENVIRONMENT="${1:-dev}"
PROJECT_PREFIX="aiops-platform"
REGION="${AWS_REGION:-eu-central-1}"

echo "Fetching configuration for environment: $ENVIRONMENT"
echo "Region: $REGION"
echo ""

# Fetch SSM Parameters
echo "=== Bedrock Configuration ==="
aws ssm get-parameter --name "/$PROJECT_PREFIX/$ENVIRONMENT/bedrock/rca_model_id" --query 'Parameter.Value' --output text 2>/dev/null || echo "RCA Model: Not configured"
aws ssm get-parameter --name "/$PROJECT_PREFIX/$ENVIRONMENT/bedrock/correlation_model_id" --query 'Parameter.Value' --output text 2>/dev/null || echo "Correlation Model: Not configured"
aws ssm get-parameter --name "/$PROJECT_PREFIX/$ENVIRONMENT/bedrock/region" --query 'Parameter.Value' --output text 2>/dev/null || echo "Bedrock Region: Not configured"
echo ""

echo "=== OpenSearch ==="
OPENSEARCH_ENDPOINT=$(aws ssm get-parameter --name "/$PROJECT_PREFIX/$ENVIRONMENT/opensearch_endpoint" --query 'Parameter.Value' --output text 2>/dev/null || echo "Not deployed")
echo "Endpoint: $OPENSEARCH_ENDPOINT"
echo ""

echo "=== DynamoDB Tables ==="
echo "Anomalies: $PROJECT_PREFIX-$ENVIRONMENT-anomalies"
echo "Events: $PROJECT_PREFIX-$ENVIRONMENT-events"
echo "Policy Store: $PROJECT_PREFIX-$ENVIRONMENT-policy-store"
echo "Agent State: $PROJECT_PREFIX-$ENVIRONMENT-agent-state"
echo ""

echo "=== S3 Buckets ==="
echo "Raw Logs: $PROJECT_PREFIX-$ENVIRONMENT-raw-logs"
echo "Audit Logs: $PROJECT_PREFIX-$ENVIRONMENT-audit-logs"
echo "Screenshots: $PROJECT_PREFIX-$ENVIRONMENT-dashboard-screenshots"
echo ""

echo "=== IAM Roles (from Terraform outputs) ==="
cd terraform/environments/$ENVIRONMENT 2>/dev/null || {
  echo "Terraform directory not found or not initialized"
  exit 0
}

if [ -f terraform.tfstate ]; then
  echo "Lambda Execution Role ARN:"
  terraform output -raw lambda_execution_role_arn 2>/dev/null || echo "  Not available"
  echo ""
  echo "Step Functions Role ARN:"
  terraform output -raw step_functions_role_arn 2>/dev/null || echo "  Not available"
else
  echo "Terraform state not found. Deploy infrastructure first with 'terraform apply'"
fi

echo ""
echo "To use these values locally, update your .env file or export as environment variables"
