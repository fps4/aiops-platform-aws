locals {
  name_prefix = "${var.project_prefix}-${var.environment}"
  # Staging dir populated by `make build-log-normalizer` (source + shared + pip deps).
  # Run `make build-lambdas` before terraform apply.
  log_normalizer_pkg = "${path.module}/.builds/log-normalizer-pkg"
}

# ─── Log-Normalizer Lambda ────────────────────────────────────────────────────

data "archive_file" "log_normalizer" {
  type        = "zip"
  source_dir  = local.log_normalizer_pkg
  output_path = "${path.module}/.builds/log-normalizer.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_lambda_function" "log_normalizer" {
  function_name = "${local.name_prefix}-log-normalizer"
  role          = var.lambda_execution_role_arn
  runtime       = "python3.13"
  handler       = "handler.lambda_handler"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.log_normalizer.output_path
  source_code_hash = data.archive_file.log_normalizer.output_base64sha256

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = var.opensearch_endpoint
      OPENSEARCH_SERVICE  = var.opensearch_service
      RAW_LOGS_BUCKET     = var.raw_logs_bucket_name
      ENVIRONMENT         = var.environment
      PROJECT_PREFIX      = var.project_prefix
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_lambda_permission" "firehose_invoke" {
  statement_id  = "AllowFirehoseInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_normalizer.function_name
  principal     = "firehose.amazonaws.com"
}

# ─── Kinesis Firehose ─────────────────────────────────────────────────────────

resource "aws_kinesis_firehose_delivery_stream" "log_stream" {
  name        = "${local.name_prefix}-log-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = var.firehose_delivery_role_arn
    bucket_arn = var.raw_logs_bucket_arn

    prefix              = "logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = 1
    buffering_interval = 60

    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.log_normalizer.arn}:$LATEST"
        }

        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = "1"
        }

        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = "60"
        }
      }
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── CloudWatch Logs Destination ──────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# CWL needs a role it can assume (trust: logs.amazonaws.com) with permission
# to put records into Firehose. The Firehose delivery role trusts
# firehose.amazonaws.com and cannot be assumed by CWL.
resource "aws_iam_role" "cloudwatch_logs_subscription" {
  name = "${local.name_prefix}-cwl-subscription"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "cloudwatch_logs_subscription" {
  name = "${local.name_prefix}-cwl-subscription-policy"
  role = aws_iam_role.cloudwatch_logs_subscription.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = [aws_kinesis_firehose_delivery_stream.log_stream.arn]
    }]
  })
}

resource "aws_cloudwatch_log_destination" "logs_destination" {
  name       = "${local.name_prefix}-logs-destination"
  role_arn   = aws_iam_role.cloudwatch_logs_subscription.arn
  target_arn = aws_kinesis_firehose_delivery_stream.log_stream.arn

  depends_on = [aws_iam_role_policy.cloudwatch_logs_subscription]
}

resource "aws_cloudwatch_log_destination_policy" "logs_destination" {
  destination_name = aws_cloudwatch_log_destination.logs_destination.name

  # Allow member accounts (and the central account itself) to put subscription filters
  access_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSubscriptionFilters"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "logs:PutSubscriptionFilter"
        Resource = aws_cloudwatch_log_destination.logs_destination.arn
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = "*"
          }
        }
      }
    ]
  })
}
