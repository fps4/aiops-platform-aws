# MVP Development Plan

**Goal**: Deliver end-to-end proactive anomaly detection with AI-assisted RCA and Slack alerting.

**Region**: eu-central-1  
**Target**: Support 5 test accounts initially, scale to 20+ accounts by MVP completion

---

## Implementation Steps Overview

| Step | Focus | Key Deliverables |
|------|-------|------------------|
| **Step 1** | Foundation & Infrastructure | Terraform modules, IAM, data stores |
| **Step 2** | Data Ingestion & Normalization | CloudWatch → OpenSearch pipeline |
| **Step 3** | Anomaly Detection | Statistical + rule-based detectors |
| **Step 4** | Agentic Orchestration | Step Functions + Detection/Correlation agents |
| **Step 5** | RCA & AI Integration | RCA agent with Bedrock Claude |
| **Step 6** | Alerting & Dashboards | Slack notifications + OpenSearch dashboards |

---

## Step 1: Foundation & Infrastructure

**Goal**: Establish AWS infrastructure foundation with reusable Terraform modules.

### Step 1.1: Core Infrastructure

#### Tasks
- [ ] **1.1.1 Setup Project Structure**
  - Initialize Git repository with folder structure from README.md
  - Setup pre-commit hooks (Terraform fmt, Python linting)
  - Configure GitHub repository settings

- [ ] **1.1.2 Terraform Networking Module**
  - VPC with 3 private subnets (eu-central-1a/b/c)
  - VPC endpoints: S3, DynamoDB, Secrets Manager, Lambda
  - Security groups with least privilege rules

- [ ] **1.1.3 Terraform IAM Module**
  - Central account IAM roles (Lambda, Step Functions, SageMaker)
  - Cross-account role template for member accounts
  - IAM policies for observability (read CloudWatch, write to Kinesis)

- [ ] **1.1.4 Terraform Data Stores Module**
  - S3 buckets: raw-logs, audit-logs, dashboards-screenshots (with lifecycle)
  - DynamoDB tables: anomalies, events, policy_store, agent_state, audit_logs
  - OpenSearch Serverless collection with IAM auth
  - Timestream database and table for metrics

#### Deliverables
- ✅ Terraform modules: networking, iam, data-stores
- ✅ Environment configs: terraform/environments/dev/
- ✅ All infrastructure deployable with `terraform apply`
- ✅ Documentation: terraform/README.md with usage examples

#### Success Criteria
- Terraform plan succeeds without errors
- All AWS resources created in eu-central-1
- OpenSearch accessible via IAM authentication
- DynamoDB tables queryable

---

### Step 1.2: Compute & Cross-Account Setup

#### Tasks
- [ ] **1.2.1 Terraform Compute Module**
  - Lambda execution role with permissions
  - Lambda layer for shared dependencies (boto3, requests, etc.)
  - Step Functions IAM role and basic state machine template
  - CloudWatch Log Groups for all Lambda functions

- [ ] **1.2.2 Member Account Setup Module**
  - Terraform module: terraform/member-account/
  - ObservabilityWriteRole (write to Kinesis, EventBridge)
  - ObservabilityReadRole (read CloudWatch metrics)
  - Trust policy to central account

- [ ] **1.2.3 Secrets & Configuration Management**
  - Secrets Manager: Slack webhook URL placeholder
  - Systems Manager Parameter Store: region, retention_days, sensitivity_default
  - DynamoDB policy_store: load initial schema

- [ ] **1.2.4 Observability Module**
  - CloudWatch alarms: Lambda errors, Step Functions failures
  - CloudWatch dashboard: pipeline health metrics
  - X-Ray tracing enabled for Step Functions

- [ ] **1.2.5 Deploy to 2 Test Accounts**
  - Deploy member-account module to dev-account-1, dev-account-2
  - Validate IAM role assumption from central account
  - Test CloudWatch Logs subscription filter creation

#### Deliverables
- ✅ Terraform modules: compute, observability
- ✅ Member account setup deployed to 2 test accounts
- ✅ Secrets Manager and Parameter Store configured
- ✅ CloudWatch alarms and dashboards created

#### Success Criteria
- Central account can assume roles in member accounts
- Lambda can read/write to DynamoDB, S3, OpenSearch
- Step Functions can invoke Lambda functions
- CloudWatch alarms trigger on test errors

---

## Step 2: Data Ingestion & Normalization

**Goal**: Ingest logs, metrics, and events from member accounts into central storage.

### Step 2.1: Log & Metric Ingestion

#### Tasks
- [ ] **2.1.1 Kinesis Firehose Setup**
  - Create Firehose delivery stream: CloudWatch Logs → S3 (raw)
  - Configure buffering: 5MB or 60 seconds
  - S3 partitioning: s3://raw-logs/account_id=123/service=api-gateway/date=2026-02-14/

- [ ] **2.1.2 CloudWatch Logs Subscription Filters**
  - Script: scripts/setup-log-subscriptions.sh
  - Create subscription filters for Lambda, ECS, RDS, ALB logs
  - Test with 2 member accounts

- [ ] **2.1.3 Log Normalization Lambda**
  - Lambda: src/ingestion/lambda/log-normalizer/
  - Parse raw logs to canonical JSON schema
  - Enrich with account_id, region, service metadata
  - Write to OpenSearch Serverless

- [ ] **2.1.4 Metrics Ingestion**
  - Configure CloudWatch cross-account metrics sharing
  - Lambda to query CloudWatch metrics every 1 minute
  - Write to Timestream: p50/p95/p99 latency, error_rate, request_rate

#### Deliverables
- ✅ Kinesis Firehose pipeline: CloudWatch → S3 → Lambda → OpenSearch
- ✅ Log normalization Lambda with unit tests
- ✅ Metrics ingestion Lambda writing to Timestream
- ✅ Logs from 2 accounts visible in OpenSearch

#### Success Criteria
- 10,000 logs/minute ingested without data loss
- End-to-end latency < 30 seconds (CloudWatch → OpenSearch)
- Canonical schema validated in OpenSearch
- Timestream shows metrics with 1-minute granularity

---

### Step 2.2: Event Ingestion & Enrichment

#### Tasks
- [ ] **2.2.1 EventBridge Cross-Account Bus**
  - Create central EventBridge bus
  - Setup rules in member accounts: forward deployment events, autoscaling, health checks

- [ ] **2.2.2 Event Processor Lambda**
  - Lambda: src/ingestion/lambda/event-processor/
  - Parse EventBridge events to canonical format
  - Write to DynamoDB events table with TTL (90 days)
  - Extract deployment metadata (version, timestamp)

- [ ] **2.2.3 Deployment Metadata Enrichment**
  - Query DynamoDB events for recent deployments
  - Enrich logs with deployment_version, deployment_timestamp
  - Add to OpenSearch documents

- [ ] **2.2.4 Schema Validation & Testing**
  - Define JSON schemas: src/ingestion/schemas/
  - Add schema validation to Lambda functions
  - Integration tests: test_ingestion.py

#### Deliverables
- ✅ EventBridge pipeline: member accounts → central bus → DynamoDB
- ✅ Event processor Lambda with schema validation
- ✅ Logs enriched with deployment metadata
- ✅ Integration tests passing

#### Success Criteria
- Deployment events appear in DynamoDB within 5 seconds
- Logs show deployment_version field after enrichment
- Schema validation catches malformed events
- 95% test coverage for ingestion pipeline

---

## Step 3: Anomaly Detection

**Goal**: Detect anomalies using statistical and rule-based methods.

### Step 3.1: Detection Algorithms & Pipeline

#### Tasks
- [ ] **3.1.1 Statistical Detection - Baseline Calculation**
  - Lambda: src/detection/statistical/baseline.py
  - Query Timestream for 7-day historical data
  - STL decomposition for seasonality extraction
  - Store baselines in DynamoDB with service/metric key

- [ ] **3.1.2 Statistical Detection - Anomaly Scoring**
  - Lambda: src/detection/statistical/scoring.py
  - Z-score calculation: (current - baseline) / stddev
  - EWMA smoothing for noisy metrics
  - Configurable sensitivity: low/medium/high (4σ/3σ/2σ)

- [ ] **3.1.3 Statistical Detection - Change-Point Detection**
  - Lambda: src/detection/statistical/changepoint.py
  - PELT algorithm for sudden metric shifts
  - Detect deployment-induced changes

- [ ] **3.1.4 Rule-Based Detection**
  - Lambda: src/detection/rules/error_rate.py (>5% for 5 minutes)
  - Lambda: src/detection/rules/latency.py (>2x baseline for 3 minutes)
  - Lambda: src/detection/rules/security.py (IAM policy changes)

- [ ] **3.1.5 Anomaly Writer & Trigger**
  - Write detected anomalies to DynamoDB anomalies table
  - DynamoDB Stream trigger to start Step Functions workflow
  - Anomaly object schema: anomaly_id, timestamp, signal, deviation, confidence

- [ ] **3.1.6 Detection Policy Configuration**
  - YAML schema: policies/schemas/detection-policy.yaml
  - Example policies: policies/examples/latency-spike.yaml
  - Script: scripts/load-policies.sh to upload to DynamoDB

#### Deliverables
- ✅ Statistical detection Lambdas (baseline, scoring, changepoint)
- ✅ Rule-based detection Lambdas (error_rate, latency, security)
- ✅ Anomaly objects written to DynamoDB
- ✅ Detection policies loadable via script

#### Success Criteria
- Baseline calculation completes in <10 seconds per service
- Z-score anomaly detection triggers on synthetic spike
- Rule-based detection fires within 1 minute of threshold breach
- Policies loaded from YAML without errors

---

## Step 4: Agentic Orchestration

**Goal**: Build Step Functions workflow with Detection and Correlation agents.

### Step 4.1: Agent Development

#### Tasks
- [ ] **4.1.1 Step Functions State Machine**
  - Define JSON state machine: src/orchestration/step-functions/anomaly-workflow.json
  - States: DetectionAgent → CorrelationAgent → HistoricalCompare → RCAAgent → RecommendationAgent → FormatAlert
  - Add error handling and retries

- [ ] **4.1.2 Detection Agent**
  - Lambda: src/agents/detection-agent/
  - Deduplicate anomalies (same service + signal within 30 minutes)
  - Apply suppression rules from policy (cooldown_minutes)
  - Decide escalation (confidence > threshold)

- [ ] **4.1.3 Correlation Agent**
  - Lambda: src/agents/correlation-agent/
  - Query DynamoDB events for deployments in last 30 minutes
  - Query anomalies table for related anomalies (same account, nearby services)
  - Enrich anomaly object with correlated_events[]

- [ ] **4.1.4 Historical Comparison Agent**
  - Lambda: src/agents/historical-compare-agent/
  - Query past anomalies with similar characteristics
  - Retrieve past RCA results from DynamoDB
  - Calculate similarity score (service, signal, deviation)

- [ ] **4.1.5 Agent State Management**
  - Store workflow state in DynamoDB agent_state table
  - Enable workflow resume on Lambda timeout
  - Add state persistence between agents

#### Deliverables
- ✅ Step Functions state machine deployed
- ✅ Detection Agent Lambda with deduplication logic
- ✅ Correlation Agent Lambda joining events
- ✅ Historical Comparison Agent with similarity scoring
- ✅ DynamoDB agent_state table in use

#### Success Criteria
- Step Functions workflow executes end-to-end
- Anomaly triggers workflow within 10 seconds
- Detection Agent suppresses duplicate anomalies
- Correlation Agent finds deployment events
- Historical Comparison returns similar past incidents

---

## Step 5: RCA & AI Integration

**Goal**: Implement RCA agent with AWS Bedrock Claude integration.

### Step 5.1: AI-Powered Root Cause Analysis

#### Tasks
- [ ] **5.1.1 AI Provider Abstraction Layer**
  - Interface: src/ai-provider/interface.py (abstract base class)
  - Bedrock implementation: src/ai-provider/bedrock_provider.py
  - Methods: generate(), get_cost_per_token(), get_model_info()

- [ ] **5.1.2 RCA Agent - Deployment Correlation Scenario**
  - Lambda: src/agents/rca-agent/
  - Scenario 1: Check if deployment happened in last 30 min
  - Prompt engineering: structured RCA output (cause, confidence, evidence)
  - Call Bedrock Claude Sonnet with context

- [ ] **5.1.3 RCA Agent - Infrastructure & Dependency Scenarios**
  - Scenario 2: Autoscaling, instance failures, AZ issues
  - Scenario 3: Downstream service error propagation
  - Scenario 4: Resource exhaustion (OOM, throttling)
  - Scenario 5: Security/access issues (IAM, network)

- [ ] **5.1.4 Recommendation Agent**
  - Lambda: src/agents/recommendation-agent/
  - Map RCA probable cause to runbook links (placeholder URLs)
  - Suggest next steps (rollback, scale, investigate)

- [ ] **5.1.5 Cost Tracking & Audit Logging**
  - Log all Bedrock calls: src/ai-provider/cost_tracker.py
  - Write to S3 audit-logs: prompt, response, tokens, cost, latency
  - DynamoDB cost tracking table with daily aggregation
  - CloudWatch alarm on daily spend > $100

- [ ] **5.1.6 Per-Agent Provider Configuration**
  - DynamoDB policy_store: ai_provider_config
  - Load agent-type → provider mapping from YAML
  - Example: rca_agent uses Claude Sonnet, correlation_agent uses Haiku

#### Deliverables
- ✅ AI provider abstraction with Bedrock implementation
- ✅ RCA Agent Lambda with 5 investigation scenarios
- ✅ Recommendation Agent Lambda
- ✅ Audit logging to S3 for all AI calls
- ✅ Per-agent AI provider configuration

#### Success Criteria
- RCA Agent successfully calls Bedrock Claude
- Generates structured JSON response: cause, confidence, evidence
- All 5 scenarios tested with synthetic anomalies
- Audit logs show prompt/response for debugging
- Cost tracking dashboard shows spend per agent

---

## Step 6: Alerting & Dashboards

**Goal**: Deliver Slack alerts and OpenSearch dashboards.

### Step 6.1: Alert Delivery & Visualization

#### Tasks
- [ ] **6.1.1 Slack Notifier Lambda**
  - Lambda: src/alerting/slack-notifier/handler.py
  - Format alert payload: Block Kit JSON
  - Sections: Header, What Happened, Probable Cause, Evidence, View Dashboard button
  - Post to #aiops-alerts channel

- [ ] **6.1.2 OpenSearch Dashboard Deep-Link Generator**
  - Module: src/alerting/slack-notifier/deeplink.py
  - Generate URL with query parameters: time, service, account_id, anomaly_id
  - Pre-filter dashboard to incident timeframe (±30 minutes)

- [ ] **6.1.3 OpenSearch Dashboard - Unified Timeline**
  - Dashboard: dashboards/unified-timeline.ndjson
  - Visualizations: Timeline bars (anomalies, deployments, events)
  - Filters: Account, region, service, severity, time range

- [ ] **6.1.4 OpenSearch Dashboard - Anomaly Detection Results**
  - Dashboard: dashboards/anomaly-results.ndjson
  - Visualizations: Line chart (current vs baseline), heatmap, table
  - Filters: Confidence level, deviation %, service

- [ ] **6.1.5 OpenSearch Dashboard - RCA Evidence Explorer**
  - Dashboard: dashboards/rca-evidence-explorer.ndjson
  - Layout: RCA summary (top), logs (left), metrics (center), events (right)
  - Deep-linkable via anomaly_id parameter

- [ ] **6.1.6 Dashboard Import Script**
  - Script: scripts/import-opensearch-dashboards.sh
  - Import .ndjson files to OpenSearch via API
  - Handle index patterns and saved objects

- [ ] **6.1.7 End-to-End Testing**
  - Script: scripts/generate-test-anomaly.sh
  - Inject synthetic latency spike into test account
  - Validate: Anomaly detected → RCA generated → Slack alert received
  - Verify: OpenSearch dashboard loads with pre-filtered data

#### Deliverables
- ✅ Slack notifier Lambda with rich Block Kit formatting
- ✅ 3 OpenSearch dashboards (timeline, anomalies, evidence)
- ✅ Dashboard import script
- ✅ End-to-end test passing (anomaly → Slack alert in <2 minutes)

#### Success Criteria
- Slack alert includes RCA summary with confidence score
- Dashboard link in Slack navigates to pre-filtered OpenSearch view
- All 3 dashboards load in <3 seconds
- Synthetic anomaly test succeeds 3 times in a row

---

## Testing Strategy

### Unit Tests
- **Coverage Target**: 80% for all Lambda functions
- **Framework**: pytest for Python, Jest for Node.js (if used)
- **Location**: src/*/tests/
- **Run**: `pytest tests/`

### Integration Tests
- **Scope**: Test inter-service communication (Lambda → DynamoDB, Lambda → OpenSearch)
- **Location**: tests/integration/
- **Run**: `pytest tests/integration/` (requires AWS credentials)

### End-to-End Tests
- **Scope**: Full pipeline from anomaly injection to Slack alert
- **Location**: tests/e2e/test_anomaly_to_slack.py
- **Run**: `pytest tests/e2e/`

### Performance Tests
- **Scope**: Load test with 10,000 logs/minute, 100 anomalies/hour
- **Tools**: Locust or AWS CloudWatch Synthetics
- **Success**: <2 minute anomaly-to-alert latency at P95

---

## Deployment Strategy

### Environments
- **dev**: Development environment with 2 test accounts
- **staging**: Pre-production with 5 accounts, mirror of prod config
- **prod**: Production with 20+ accounts (post-MVP)

### Deployment Process
1. **Code Review**: All changes require PR review
2. **Terraform Plan**: Review infrastructure changes before apply
3. **Blue/Green Lambda Deployment**: Use Lambda aliases for safe rollout
4. **Smoke Tests**: Run E2E test after deployment
5. **Rollback Plan**: Revert Terraform state, redeploy previous Lambda version

### CI/CD Pipeline (Optional for MVP)
- **GitHub Actions**: .github/workflows/
- **Stages**: Lint → Test → Terraform Plan → Deploy to dev
- **Manual Approval**: Required for staging/prod deployment

---

## Success Metrics

### MVP Definition of Done
- ✅ Ingest logs/metrics from 5 AWS accounts
- ✅ Detect 1 synthetic anomaly (latency spike)
- ✅ Generate RCA with confidence score and evidence
- ✅ Deliver Slack alert with OpenSearch dashboard link
- ✅ All 3 OpenSearch dashboards functional
- ✅ Documentation complete (README, solution design, getting started guide)
- ✅ End-to-end test passes consistently

### Performance Targets
- **Ingestion throughput**: 10,000 logs/minute per account
- **Detection latency**: Anomaly detected within 1 minute of occurrence
- **RCA generation**: Complete within 60 seconds
- **Alert delivery**: Slack notification within 2 minutes of anomaly (P95)
- **Dashboard load time**: <3 seconds for pre-filtered views

### Quality Targets
- **Test coverage**: 80% for all Lambda functions
- **False positive rate**: <10% (measured manually in MVP)
- **RCA accuracy**: 70% correct root cause (validated by engineer review)

---

## Risk Management

### High-Risk Items
| Risk | Impact | Mitigation |
|------|--------|------------|
| Bedrock API rate limits | Alert delays | Implement retry with exponential backoff, per-agent cost caps |
| OpenSearch Serverless cost | Budget overrun | Monitor usage daily, set CloudWatch alarms at 80% budget |
| Cross-account IAM issues | Data loss | Test IAM roles in 2 accounts first, validate before scaling |
| Lambda cold start latency | Slow RCA | Use provisioned concurrency for RCA agent Lambda |
| Step Functions timeout | Workflow failure | Implement state persistence, enable workflow resume |

### Contingency Plans
- **Bedrock unavailable**: Fallback to rule-based RCA (no AI), manual investigation
- **OpenSearch down**: Alerts still delivered, use CloudWatch Logs Insights for investigation
- **Budget exceeded**: Pause AI provider calls, alert on rule-based detection only

---

## Post-MVP Next Steps

### Multi-Account Rollout
- Deploy to 20 production accounts
- Load production detection policies
- Monitor for false positives, tune sensitivity

### Phase 1 Kickoff
- Screenshot generation for Slack alerts
- AI provider cost/usage dashboard
- Detection policy effectiveness metrics

---

## Documentation Requirements

### Deliverables by End of MVP
- [ ] README.md (already complete)
- [ ] docs/getting-started.md (setup guide)
- [ ] docs/detection-policies.md (policy configuration reference)
- [ ] docs/ai-providers.md (Bedrock setup guide)
- [ ] terraform/README.md (infrastructure overview)
- [ ] src/README.md (code architecture)
- [ ] CONTRIBUTING.md (contribution guidelines)

---

**Plan Status**: Ready for Implementation  
**Last Updated**: 2026-02-14  
**Implementation Approach**: Sequential steps, follow with AI Copilot
