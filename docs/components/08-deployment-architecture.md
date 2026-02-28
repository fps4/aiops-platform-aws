# Deployment Architecture

## Terraform Module Structure

```
terraform/
  modules/
    iam/           — cross-account roles, Lambda/Fargate execution roles
    data-stores/   — S3, DynamoDB, ClickHouse EC2 + EBS
    compute/       — Lambda functions, Fargate detection task, Grafana EC2, EventBridge schedules
    ingestion/     — Kinesis Firehose, log-normalizer Lambda
  environments/
    dev/           — dev.tfvars, main.tf, resources.tf, outputs.tf
```

## Module: Networking (prerequisite, external to repo)
- VPC with private subnets (no public internet access for compute)
- VPC Endpoints for AWS services (S3, DynamoDB, Secrets Manager)
- Security groups with least privilege

## Module: IAM Roles
- `ObservabilityWriteRole` (member accounts) → write to Kinesis Firehose
- `ObservabilityReadRole` (central account) → read CloudWatch metrics from members
- `LambdaExecutionRole` → read/write DynamoDB, S3, invoke Bedrock; write to ClickHouse HTTP API
- `FargateTaskRole` (statistical detector) → query ClickHouse HTTP API, write to DynamoDB
- `ClickHouseEC2InstanceProfile` → SSM Session Manager access, CloudWatch Logs write
- `GrafanaEC2InstanceProfile` → SSM Session Manager access, CloudWatch Logs write

## Module: Data Stores
- S3 buckets (raw logs, audit logs, dashboard screenshots) with lifecycle policies
- ClickHouse on plain EC2 (AL2023, t3.large, systemd): `clickhouse-server` installed via RPM, separate 100 GB gp3 EBS at `/var/lib/clickhouse`
- DynamoDB tables: `anomalies` (with Streams), `events`, `policy_store`, `agent_state`, `audit_logs`

## Module: Compute
- Lambda functions: log-normalizer, rule-based detection, orchestrator (agentic pipeline), Slack notifier
- DynamoDB Stream trigger: `anomalies` table → orchestrator Lambda
- Plain EC2 (AL2023, t3.large, systemd) for ClickHouse; separate 100 GB gp3 EBS data volume
- Plain EC2 (AL2023, t3.small, systemd) for Grafana; access via SSM port forwarding
- Fargate task definition + ECS cluster: statistical anomaly detection (scheduled)
- EventBridge Scheduler rule: triggers Fargate detection task every 5 minutes

## Module: Observability
- CloudWatch Logs for Lambda and Fargate tasks
- CloudWatch Alarms for cost caps, error rates, detection task failures
- X-Ray tracing for orchestrator Lambda

---

## Deployment Steps

### Phase: Setup Central Account

```bash
# 1. Deploy networking and IAM
terraform apply -target=module.networking -target=module.iam

# 2. Deploy data stores (ClickHouse EC2 + EBS + DynamoDB)
terraform apply -target=module.data_stores

# 3. Deploy compute (Lambda, Fargate detection, Grafana EC2)
terraform apply -target=module.compute

# 4. Provision Grafana dashboards (via provisioning YAML + API)
./scripts/provision-grafana-dashboards.sh

# 5. Configure Slack webhook
aws secretsmanager put-secret-value \
  --secret-id aiops/dev/slack-webhook \
  --secret-string '{"webhook_url": "https://hooks.slack.com/services/..."}'
```

### Phase: Configure Member Accounts

```bash
# Deploy cross-account IAM role per member account
cd member-account-setup
terraform apply \
  -var="central_account_id=123456789012" \
  -var="account_id=987654321098"

# Deploy CloudWatch Logs subscription filters
./scripts/setup-log-subscriptions.sh --account-id 987654321098
```

### Phase: Load Detection Policies

```bash
./scripts/load-policies.sh --file policies/default-policies.yaml
```

---

## Accessing Services (dev)

No public IPs or ALB. Use SSM Session Manager port forwarding:

```bash
# Grafana (port 3000)
aws ssm start-session \
  --target $(terraform -chdir=terraform/environments/dev output -raw grafana_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'

# ClickHouse (port 8123)
aws ssm start-session \
  --target $(terraform -chdir=terraform/environments/dev output -raw clickhouse_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8123"],"localPortNumber":["8123"]}'
```
