# GitHub Copilot Instructions for AIOps Platform

## Project Overview

This is an AWS-native AIOps platform that provides proactive anomaly detection with AI-assisted root cause analysis. The platform ingests observability signals from multiple AWS accounts, applies hybrid anomaly detection (statistical + rule-based), orchestrates agentic RCA workflows, and delivers Slack alerts with OpenSearch dashboard links.

**Key Architecture**: Serverless-first, multi-account, event-driven, AWS-native (Lambda, Step Functions, DynamoDB, OpenSearch, Timestream).

## Repository Structure

```
aiops-platform/
├── terraform/               # Infrastructure-as-Code (modular)
│   ├── modules/            # Reusable modules (networking, iam, data-stores, compute, etc.)
│   ├── environments/       # Environment-specific configs (dev, staging, prod)
│   └── member-account/     # Cross-account IAM setup for member accounts
├── src/                    # Application code (Lambda functions, agents)
│   ├── ingestion/          # Log/metric normalization pipeline
│   ├── detection/          # Anomaly detection (statistical + rule-based)
│   ├── agents/             # Agentic workflow components
│   ├── ai-provider/        # AI provider abstraction (Bedrock, OpenAI, self-hosted)
│   ├── alerting/           # Slack notifications, dashboard deep-links
│   ├── orchestration/      # Step Functions workflows
│   └── shared/             # Common utilities
├── policies/               # Detection policy YAML configs
├── dashboards/             # OpenSearch dashboard definitions (.ndjson)
├── scripts/                # Operational scripts (setup, import, testing)
├── tests/                  # Unit, integration, E2E tests
└── docs/                   # Design docs, development plan, requirements
```

## Development Workflow

### Current Phase
**MVP Implementation** - Follow `docs/mvp-development-plan.md` sequentially:
- Step 1: Foundation & Infrastructure
- Step 2: Data Ingestion & Normalization
- Step 3: Anomaly Detection
- Step 4: Agentic Orchestration
- Step 5: RCA & AI Integration
- Step 6: Alerting & Dashboards

**Status**: Infrastructure foundation not yet implemented. Start with Step 1.1 (project structure and Terraform modules).

### Implementation Guidelines

1. **Check the plan first**: Always reference `docs/mvp-development-plan.md` for the current step's tasks, deliverables, and success criteria
2. **Follow the sequence**: Complete tasks in order within each step
3. **Mark progress**: Update checkboxes in the plan as tasks are completed
4. **Validate**: Run success criteria tests after each step

## Architecture Patterns

### Multi-Account Ingestion Pattern
- **Member accounts**: CloudWatch Logs → Subscription Filter → Kinesis Firehose → Central Account
- **Cross-account IAM**: Member accounts assume ObservabilityWriteRole, central account assumes ObservabilityReadRole
- **Data flow**: Logs → S3 (raw) → Lambda (normalize) → OpenSearch (indexed)

### Anomaly Detection Flow
1. **Baseline**: Query Timestream for 7-day historical data, apply STL decomposition
2. **Scoring**: Calculate Z-score (current - baseline) / stddev
3. **Triggering**: Write anomaly to DynamoDB → DynamoDB Stream → Step Functions workflow

### Agentic Workflow (Step Functions)
```
Anomaly → DetectionAgent → CorrelationAgent → HistoricalCompareAgent → 
          RCAAgent → RecommendationAgent → SlackNotifier
```

- **State management**: DynamoDB agent_state table for workflow persistence
- **AI provider selection**: Per-agent configuration from DynamoDB policy_store
- **Error handling**: Retry with exponential backoff, fallback to rule-based RCA

### AI Provider Abstraction
- **Interface**: `src/ai-provider/interface.py` (abstract base class)
- **Implementations**: BedrockProvider, OpenAIProvider, SelfHostedProvider
- **Configuration**: Per-agent-type provider selection (e.g., RCA uses Claude Sonnet, correlation uses Haiku)
- **Audit**: All prompts/responses logged to S3 for compliance

## Key Conventions

### Terraform Modules
- **Modularity**: Each AWS service group is a separate module (networking, iam, data-stores, compute, ingestion, observability)
- **Reusability**: Modules accept variables for environment-specific config (dev, staging, prod)
- **Naming**: Resources prefixed with `aiops-{environment}-{resource-type}` (e.g., `aiops-dev-anomalies-table`)
- **State**: Remote state in S3, state locking via DynamoDB

### Lambda Functions
- **Structure**: Each agent/function is a directory with `handler.py`, `requirements.txt`, and `tests/`
- **Entry point**: Handler function named `lambda_handler(event, context)`
- **Logging**: Use `src/shared/logger.py` for structured logging (JSON format)
- **Config**: Load runtime config from DynamoDB policy_store or Parameter Store
- **Error handling**: Catch exceptions, log to CloudWatch, return structured error response

### DynamoDB Schema Conventions
- **Primary keys**:
  - `anomalies` table: PK=`anomaly_id`, SK=`timestamp`
  - `events` table: PK=`account_id#service`, SK=`timestamp`
  - `policy_store` table: PK=`policy_id`
  - `agent_state` table: PK=`workflow_id`, SK=`step_name`
- **TTL**: Use `ttl` attribute (Unix timestamp) for automatic expiration
- **Streams**: Enable streams on `anomalies` table to trigger Step Functions

### Canonical Data Schema
All logs normalized to this format:
```json
{
  "timestamp": "ISO8601",
  "account_id": "12-digit AWS account ID",
  "region": "AWS region",
  "service": "service name (e.g., api-gateway)",
  "environment": "dev|staging|prod",
  "log_level": "ERROR|WARN|INFO|DEBUG",
  "message": "log message",
  "deployment_version": "version string",
  "deployment_timestamp": "ISO8601",
  "related_events": ["event_id_1", "event_id_2"]
}
```

### Detection Policy YAML Format
```yaml
detection_policies:
  - name: policy-name
    scope:
      accounts: ["account-id-1", "account-id-2"]
      services: ["service-1", "service-2"]
    detection:
      type: statistical|rule-based
      metric: metric_name
      baseline_window: 7d
      sensitivity: low|medium|high
      threshold:
        z_score: 3.0
        min_deviation_pct: 50
    actions:
      alert: true
      run_rca: true
      agent_provider: bedrock-claude-sonnet
      suppress_similar_minutes: 30
```

### Step Functions Workflow State
- **Input**: Anomaly object from DynamoDB
- **State passing**: Each agent enriches the state object, passed to next agent
- **Error states**: Retry 3 times with exponential backoff, then fallback or fail
- **Execution time**: Target <2 minutes end-to-end (anomaly → Slack alert)

### Testing Patterns
- **Unit tests**: Mock AWS SDK calls (boto3) using `moto` library
- **Integration tests**: Use localstack for local AWS service emulation (optional)
- **E2E tests**: Inject synthetic anomalies via `scripts/generate-test-anomaly.sh`
- **Coverage target**: 80% minimum for all Lambda functions

### OpenSearch Dashboard Deep-Linking
Dashboard URLs include query parameters for pre-filtering:
```
https://opensearch.example.com/app/dashboards#/view/{dashboard-id}
  ?time={start_time}_{end_time}
  &service={service_name}
  &account_id={account_id}
  &anomaly_id={anomaly_id}
```

## AI Provider Integration Notes

### Bedrock Claude (Primary for MVP)
- **Models**: Claude 3 Sonnet (RCA), Claude 3 Haiku (summarization)
- **Region**: Use same region as central account (eu-central-1)
- **Authentication**: IAM role, no API keys needed
- **Cost tracking**: Log input/output tokens, calculate cost via `get_cost_per_token()`

### Prompt Engineering for RCA
- **Structure**: Provide context (anomaly, deployment events, logs, past incidents), ask for JSON output
- **Format**: `{"probable_cause": "...", "confidence": "low|medium|high", "evidence": [...], "alternative_explanations": [...]}`
- **Temperature**: 0.2 for RCA (deterministic), 0.3 for recommendations (slightly creative)

### Cost Control
- **Per-agent caps**: CloudWatch alarm when daily spend exceeds configured limit
- **Fallback**: If cost cap reached, skip AI calls and use rule-based heuristics
- **Audit**: All prompts/responses logged to S3 for debugging and cost analysis

## Deployment

### Infrastructure Deployment
```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

### Lambda Deployment
```bash
cd src/agents/rca-agent
pip install -r requirements.txt -t package/
cd package && zip -r ../function.zip . && cd ..
zip -g function.zip handler.py
aws lambda update-function-code --function-name aiops-dev-rca-agent --zip-file fileb://function.zip
```

### Member Account Setup
```bash
cd terraform/member-account
terraform apply \
  -var="central_account_id=123456789012" \
  -var="account_id=987654321098"
```

### Policy Loading
```bash
scripts/load-policies.sh --file policies/default-policies.yaml
```

### Dashboard Import
```bash
scripts/import-opensearch-dashboards.sh \
  --endpoint https://opensearch.example.com
```

## Common Tasks

### Adding a New Detection Policy
1. Create YAML file: `policies/examples/new-policy.yaml`
2. Validate schema: `python scripts/validate-policy.py policies/examples/new-policy.yaml`
3. Load to DynamoDB: `scripts/load-policies.sh --file policies/examples/new-policy.yaml`

### Adding a New RCA Scenario
1. Add scenario logic to `src/agents/rca-agent/scenarios.py`
2. Update prompt template in `src/agents/rca-agent/prompts.py`
3. Add tests: `src/agents/rca-agent/tests/test_scenarios.py`
4. Update documentation: `docs/3-solution-design.md` (RCA scenarios section)

### Adding a New AI Provider
1. Implement interface: `src/ai-provider/new_provider.py` (inherit from `AIProvider`)
2. Add configuration: DynamoDB policy_store `ai_provider_config`
3. Update provider factory: `src/ai-provider/factory.py`
4. Add tests: `src/ai-provider/tests/test_new_provider.py`

### Debugging Step Functions Workflow
1. Check execution history in AWS Console: Step Functions → Execution details
2. Review CloudWatch Logs for each Lambda function
3. Query DynamoDB agent_state table for workflow state
4. Check S3 audit logs for AI provider calls

## Important References

- **Architecture**: `docs/3-solution-design.md` (detailed component design)
- **Requirements**: `docs/2-requirements-ux.md` (user workflows, success criteria)
- **MVP Plan**: `docs/mvp-development-plan.md` (implementation checklist)
- **Features**: `FEATURES.md` (current vs future features)
- **Product Vision**: `docs/1-product-summary.md` (tenets, capabilities, roadmap)

## Do Not

- **Do not modify Step Functions workflow** without updating `src/orchestration/step-functions/anomaly-workflow.json`
- **Do not change canonical schema** without migrating existing OpenSearch indices
- **Do not add dependencies** to Lambda functions without updating `requirements.txt` and rebuilding deployment package
- **Do not skip security best practices**: Always use IAM roles (never hardcoded credentials), enable encryption at rest/transit, follow least privilege
- **Do not commit secrets**: Use AWS Secrets Manager or Parameter Store, never commit API keys or credentials
- **Do not bypass policy configuration**: Always load policies via YAML → DynamoDB, not hardcoded in Lambda

## Performance Targets (MVP)

- **Ingestion throughput**: 10,000 logs/minute per account
- **Detection latency**: Anomaly detected within 1 minute of occurrence
- **RCA generation**: Complete within 60 seconds
- **Alert delivery**: Slack notification within 2 minutes (P95)
- **Dashboard load time**: <3 seconds for pre-filtered views

## Region & Multi-Account Setup

- **Central account region**: eu-central-1 (all control plane resources)
- **Member accounts**: Can be any region, logs forwarded to central account
- **Cross-region**: Not supported in MVP, single-region deployment only
- **Account limit**: MVP targets 5 test accounts, scales to 20+ in production
