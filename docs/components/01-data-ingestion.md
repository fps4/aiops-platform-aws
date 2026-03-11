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

## Role and activity guide mapping

- **Platform Team**: ingestion pipeline ownership and cross-account setup  
  See [../guidelines/platform-team.md](../guidelines/platform-team.md)
- **Product Engineering Teams**: service onboarding and telemetry quality  
  See [../guidelines/product-engineering-teams.md](../guidelines/product-engineering-teams.md)
- **Security & Compliance**: cross-account access and data handling controls  
  See [../guidelines/security-compliance.md](../guidelines/security-compliance.md)
- **Activity runbook**: onboarding log subscriptions  
  See [../guidelines/subscribing-to-the-platform.md](../guidelines/subscribing-to-the-platform.md)
