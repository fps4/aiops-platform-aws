resource "aws_cloudwatch_log_subscription_filter" "this" {
  name            = "${var.project_prefix}-${var.environment}-${var.application_name}"
  log_group_name  = var.log_group_name
  filter_pattern  = var.filter_pattern
  destination_arn = var.firehose_stream_arn
  role_arn        = var.cloudwatch_logs_subscription_role_arn
}
