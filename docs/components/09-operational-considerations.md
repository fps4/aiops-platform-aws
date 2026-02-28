# Operational Considerations

## Monitoring & Alerting

- **Pipeline health**: CloudWatch alarms on Lambda errors, Fargate task failures, orchestrator Lambda failures
- **Data lag**: Alert if ClickHouse write lag > 5 minutes (monitor via CloudWatch custom metric from normalizer Lambda)
- **Cost**: Daily budget alerts on AI provider spend, S3/EBS/EC2 usage
- **RCA accuracy**: Track confidence vs engineer validation (Phase 2 feedback loop)

## Disaster Recovery

- **Data loss**: S3 cross-region replication for raw logs (optional for Phase 2)
- **Control plane**: Terraform state in S3 with versioning; infrastructure reproducible in < 1 hour
- **ClickHouse**: systemd auto-restart on failure (`Restart=on-failure`); data persists on a separate EBS volume that survives instance replacement; daily EBS snapshots to S3

## Security

- **Encryption**: S3/DynamoDB encryption at rest (AES-256), TLS in transit
- **Access control**: IAM roles only, no long-lived credentials; EC2 instances accessed via SSM Session Manager (no SSH keys, no bastion host)
- **Audit trail**: All AI prompts/responses logged to S3 for compliance
- **Grafana**: API key authentication for dashboard access and screenshot generation (Phase 1)

## Cost Optimization

- **Compute**: Lambda scales to zero (pay-per-invocation); Fargate pay-per-second (~$1–3/month for detection task); EC2 instances on 1-year reserved pricing for predictable workloads
- **Storage**: S3 Intelligent-Tiering for raw logs; EBS gp3 for ClickHouse (~$10/month per 100 GB)
- **EC2 reserved**: t3.large 1-year reserved (~$42/month) reduces on-demand cost by ~38% for ClickHouse; t3.small 1-year reserved (~$9/month) for Grafana
- **AI providers**: Per-agent cost caps in policy config; option to route high-volume agents (correlation) to self-hosted LLMs
