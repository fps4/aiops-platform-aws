# Data Ingestion

## Sources

- **CloudWatch Logs**: Application logs, Lambda logs, ALB/NLB access logs
- **CloudWatch Metrics**: EC2, RDS, Lambda, EKS, custom application metrics
- **CloudTrail**: API activity, IAM/security events, configuration changes, deployment events

## Transport Mechanisms

- **Logs + Events**: CloudWatch Logs Subscription Filter → Kinesis Data Firehose (cross-account)
- **Metrics**: CloudWatch cross-account observability (direct read access)

CloudTrail writes to CloudWatch Logs, so all events (deployments, autoscaling, config changes) flow through the same Kinesis Firehose pipeline.

## Cross-Account IAM

- Member accounts assume `ObservabilityWriteRole` (write to Kinesis Firehose)
- Central account assumes `ObservabilityReadRole` per member (read CloudWatch metrics)
- Least privilege: deny destructive actions, restrict to observability APIs only
