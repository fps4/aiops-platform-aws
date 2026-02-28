# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWS-native AIOps platform: serverless observability control plane that ingests signals from multiple AWS accounts, applies hybrid anomaly detection (statistical + rule-based), orchestrates agentic RCA workflows via an orchestrator Lambda, and delivers Slack alerts with Grafana dashboard links.

**Region**: eu-central-1 (single-region, all resources). **Python 3.13+**. **Terraform >= 1.5**.

## Development Commands

```bash
# Setup
python3.13 -m venv venv && source venv/bin/activate
pip install boto3 python-dotenv
cp .env.example .env

# Terraform (always use var-file)
cd terraform/environments/dev
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars

# Bootstrap Terraform state backend (first time only)
./scripts/bootstrap-terraform-state.sh

# Fetch deployed resource config into .env
./scripts/get-config.sh dev

# Test Bedrock connectivity
python src/shared/bedrock_client.py

# Tests
pytest tests/                    # unit tests
pytest tests/integration/        # integration (requires AWS credentials)
pytest tests/e2e/                # end-to-end
pytest tests/path/to/test.py -k "test_name"  # single test

# Policy management
python scripts/validate-policy.py policies/default-policies.yaml
scripts/load-policies.sh --file policies/default-policies.yaml
```

## Architecture

### Data Flow
```
Member AWS Accounts → CloudWatch Logs → Subscription Filter → Kinesis Firehose
  → Lambda (log-normalizer) → S3 (raw) + ClickHouse (EC2, aiops.logs table)
  CloudTrail → CloudWatch Logs → same Kinesis Firehose pipeline
```

### Anomaly Detection → RCA Pipeline
```
ClickHouse metrics → Fargate scheduled task (every 5 min):
                     STL baseline, Z-score, PELT changepoint
                   → Rule-based detection via Lambda (error rate, latency, security)
                   → DynamoDB anomalies table → DynamoDB Stream
                   → Orchestrator Lambda (sequential agent pipeline):
                     DetectionAgent → CorrelationAgent → HistoricalCompareAgent →
                     RCAAgent (Bedrock Claude) → RecommendationAgent → SlackNotifier
```

### Observability Stack
- **Storage**: ClickHouse (plain Linux EC2, t3.large, AL2023, systemd) — tables `aiops.logs`, `aiops.anomalies`; separate 100 GB gp3 EBS at `/var/lib/clickhouse`
- **Dashboards**: Grafana (plain Linux EC2, t3.small, AL2023, systemd) with `grafana-clickhouse-datasource` plugin
- **Access**: No public IPs or ALB. Use SSM Session Manager port forwarding for dev:
  ```bash
  # Grafana (port 3000)
  aws ssm start-session --target $(terraform -chdir=terraform/environments/dev output -raw grafana_instance_id) \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
  # then open http://localhost:3000

  # ClickHouse (port 8123) — same pattern, use clickhouse_instance_id output
  ```
- **Client**: `src/shared/clickhouse_client.py` using `clickhouse-connect` (HTTP port 8123)
- **Schema**: `scripts/init-clickhouse-schema.sql` — run once after ClickHouse starts
- **Env vars**: `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (8123), `GRAFANA_URL`
- **See**: `docs/decisions/001-observability-storage-and-visualization.md`

### AI Provider Abstraction
- Abstract base class: `src/ai-provider/interface.py`
- Per-agent model selection: RCA uses Claude Sonnet, correlation uses Haiku
- Factory pattern via `create_bedrock_client(agent_type="rca|correlation|remediation")`
- Config loaded from env vars or SSM Parameter Store (`/aiops-platform/{env}/bedrock/`)
- All AI calls audited to S3 with prompt, response, tokens, cost

## Key Conventions

### Terraform
- Modular: `terraform/modules/{iam,data-stores,compute,ingestion,observability}`
- Resource naming: `aiops-{environment}-{resource-type}` (e.g., `aiops-dev-anomalies-table`)
- State backend: S3 bucket `{account-id}-aiops-platform-terraform-state`, key `{env}/terraform.tfstate`
- Each environment has its own `{env}.tfvars`, `main.tf`, `resources.tf`

### Lambda Functions
- Structure: each agent is a directory with `handler.py`, `requirements.txt`, `tests/`
- Entry point: `lambda_handler(event, context)`
- Use `src/shared/logger.py` for structured JSON logging
- Runtime config from DynamoDB `policy_store` or SSM Parameter Store

### DynamoDB Tables
| Table | PK | SK |
|-------|----|----|
| anomalies | anomaly_id | timestamp |
| events | account_id#service | timestamp |
| policy_store | policy_id | - |
| agent_state | workflow_id | step_name |

All tables use `ttl` attribute (Unix timestamp) for expiration. Streams enabled on `anomalies` to trigger orchestrator Lambda.

### Detection Policies (YAML)
Loaded via `scripts/load-policies.sh` into DynamoDB. Schema: scope (accounts, services) + detection config (type, metric, sensitivity, threshold) + actions (alert, run_rca, agent_provider, suppression).

### Canonical Log Schema
All logs normalized to: `{timestamp, account_id, region, service, environment, log_level, message, deployment_version, deployment_timestamp, related_events}`.

## Important Rules

- Never modify the canonical log schema without migrating existing ClickHouse tables (`ALTER TABLE aiops.logs ADD COLUMN ...`)
- Never add Lambda dependencies without updating the corresponding `requirements.txt` and rebuilding the deployment zip
- Always load detection policies via YAML -> DynamoDB (never hardcode in Lambda)
- Use IAM roles for all AWS auth (never hardcoded credentials)
- Bedrock prompt temperature: 0.2 for RCA (deterministic), 0.3 for recommendations
