# Lambda Execution Role
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_prefix}-${var.environment}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Lambda Basic Execution Policy (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Custom Policy for AIOps Services
resource "aws_iam_role_policy" "lambda_aiops" {
  name = "${var.project_prefix}-${var.environment}-lambda-aiops-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          "arn:aws:dynamodb:*:${var.central_account_id}:table/${var.project_prefix}-${var.environment}-*"
        ]
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_prefix}-${var.environment}-*",
          "arn:aws:s3:::${var.project_prefix}-${var.environment}-*/*"
        ]
      },
      {
        Sid    = "OpenSearchAccess"
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = [
          "arn:aws:aoss:*:${var.central_account_id}:collection/*"
        ]
      },
      {
        Sid    = "TimestreamAccess"
        Effect = "Allow"
        Action = [
          "timestream:WriteRecords",
          "timestream:Select",
          "timestream:DescribeTable",
          "timestream:DescribeDatabase"
        ]
        # Note: Timestream is optional - permissions won't error if service not enabled
        Resource = [
          "arn:aws:timestream:*:${var.central_account_id}:database/${var.project_prefix}-${var.environment}-metrics",
          "arn:aws:timestream:*:${var.central_account_id}:database/${var.project_prefix}-${var.environment}-metrics/table/*"
        ]
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:*:${var.central_account_id}:secret:${var.project_prefix}/${var.environment}/*"
        ]
      },
      {
        Sid    = "SSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:*:${var.central_account_id}:parameter/${var.project_prefix}/${var.environment}/*"
        ]
      },
      {
        Sid    = "BedrockAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*"
        ]
      }
    ]
  })
}

# Step Functions Execution Role
resource "aws_iam_role" "step_functions_execution" {
  name = "${var.project_prefix}-${var.environment}-stepfunctions-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Step Functions Policy
resource "aws_iam_role_policy" "step_functions_aiops" {
  name = "${var.project_prefix}-${var.environment}-stepfunctions-policy"
  role = aws_iam_role.step_functions_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:*:${var.central_account_id}:function:${var.project_prefix}-${var.environment}-*"
        ]
      },
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          "arn:aws:dynamodb:*:${var.central_account_id}:table/${var.project_prefix}-${var.environment}-agent-state"
        ]
      },
      {
        Sid    = "XRayAccess"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Firehose Delivery Role (for CloudWatch Logs → S3)
resource "aws_iam_role" "firehose_delivery" {
  name = "${var.project_prefix}-${var.environment}-firehose-delivery"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "firehose_delivery_policy" {
  name = "${var.project_prefix}-${var.environment}-firehose-policy"
  role = aws_iam_role.firehose_delivery.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_prefix}-${var.environment}-raw-logs",
          "arn:aws:s3:::${var.project_prefix}-${var.environment}-raw-logs/*"
        ]
      },
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:*:${var.central_account_id}:function:${var.project_prefix}-${var.environment}-log-normalizer"
        ]
      }
    ]
  })
}

# Cross-Account Read Role (for member accounts to assume)
# Only created if member_account_ids is not empty
resource "aws_iam_role" "cross_account_read" {
  count = length(var.member_account_ids) > 0 ? 1 : 0
  
  name = "${var.project_prefix}-${var.environment}-cross-account-read"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = [for account_id in var.member_account_ids : "arn:aws:iam::${account_id}:root"]
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "cross_account_read_policy" {
  count = length(var.member_account_ids) > 0 ? 1 : 0
  
  name = "${var.project_prefix}-${var.environment}-cross-account-read-policy"
  role = aws_iam_role.cross_account_read[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetricsRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = ["*"]
      }
    ]
  })
}
