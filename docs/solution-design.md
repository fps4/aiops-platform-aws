# Solution Design

## Architecture Overview

The AIOps Platform is a **centralized observability control plane** that ingests signals from multiple AWS accounts, applies hybrid anomaly detection, orchestrates agentic RCA workflows, and delivers proactive alerts via Slack with OpenSearch dashboard integration.

**Architecture Principles**:
- **AWS-native**: Leverage managed services to minimize operational overhead
- **Serverless-first**: Lambda, Step Functions, and managed data stores where possible
- **Deterministic orchestration**: Workflows are replayable, auditable, and transparent
- **Pluggable AI**: Support multiple AI providers via unified abstraction layer
- **Multi-account by design**: Central observability account with cross-account read roles

---

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AWS Accounts (Member)                            │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │
│  │  CloudWatch    │  │  CloudTrail    │  │  VPC Flow Logs │            │
│  │  Logs/Metrics  │  │  Events        │  │  ALB/RDS/EKS   │            │
│  └────────┬───────┘  └────────┬───────┘  └────────┬───────┘            │
│           │                   │                   │                      │
│           └───────────────────┴───────────────────┘                      │
│                               │                                          │
│                    ┌──────────▼──────────┐                               │
│                    │ CloudWatch Logs     │                               │
│                    │ Subscription Filter │                               │
│                    └──────────┬──────────┘                               │
└───────────────────────────────┼──────────────────────────────────────────┘
                                │
                    Cross-Account Transport
                    (Kinesis Firehose, EventBridge)
                                │
┌───────────────────────────────▼──────────────────────────────────────────┐
│                   Central Observability Account (eu-central-1)            │
│                                                                            │
│  ┌─────────────────────── Data Plane ───────────────────────────┐        │
│  │                                                                │        │
│  │  ┌───────────────┐      ┌───────────────┐   ┌──────────────┐ │        │
│  │  │ Kinesis       │─────▶│ Lambda        │──▶│ S3 (Raw)     │ │        │
│  │  │ Firehose      │      │ Normalization │   │ Partitioned  │ │        │
│  │  └───────────────┘      └───────┬───────┘   └──────────────┘ │        │
│  │                                 │                              │        │
│  │                         ┌───────▼───────┐                      │        │
│  │                         │ OpenSearch    │◀─── Search/Viz       │        │
│  │                         │ Serverless    │                      │        │
│  │                         └───────────────┘                      │        │
│  │                                                                │        │
│  │  ┌───────────────┐      ┌───────────────┐                     │        │
│  │  │ EventBridge   │─────▶│ DynamoDB      │                     │        │
│  │  │ Events        │      │ Events Store  │                     │        │
│  │  └───────────────┘      └───────────────┘                     │        │
│  │                                                                │        │
│  │  ┌───────────────┐      ┌───────────────┐                     │        │
│  │  │ CloudWatch    │─────▶│ Timestream    │                     │        │
│  │  │ Cross-Account │      │ Metrics       │                     │        │
│  │  └───────────────┘      └───────────────┘                     │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                                                            │
│  ┌───────────────────── Detection Layer ──────────────────────────┐       │
│  │                                                                 │       │
│  │  ┌─────────────────────────────────────────────────────┐       │       │
│  │  │  Statistical Detectors (SageMaker / Lambda)         │       │       │
│  │  │  • Seasonality baselines (STL decomposition)        │       │       │
│  │  │  • Change-point detection (PELT algorithm)          │       │       │
│  │  │  • Z-score / EWMA anomaly scoring                   │       │       │
│  │  └───────────────────────┬─────────────────────────────┘       │       │
│  │                          │                                      │       │
│  │  ┌───────────────────────▼─────────────────────────────┐       │       │
│  │  │  Rule-Based Guardrails (Lambda)                     │       │       │
│  │  │  • Error rate thresholds                            │       │       │
│  │  │  • Latency regressions                              │       │       │
│  │  │  • Traffic drop detection                           │       │       │
│  │  │  • Security event patterns                          │       │       │
│  │  └───────────────────────┬─────────────────────────────┘       │       │
│  │                          │                                      │       │
│  │                  ┌───────▼────────┐                             │       │
│  │                  │  DynamoDB      │                             │       │
│  │                  │  Anomalies     │                             │       │
│  │                  └────────────────┘                             │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                            │
│  ┌────────────────── Agentic Orchestration (Step Functions) ──────────┐   │
│  │                                                                     │   │
│  │  Anomaly → [Detection Agent] → [Correlation Agent] →               │   │
│  │            [Historical Compare] → [RCA Agent] →                    │   │
│  │            [Recommendation Agent] → Alert Payload                  │   │
│  │                                                                     │   │
│  │  Agent Tasks (Lambda/Fargate):                                     │   │
│  │  • Deduplicate & suppress noisy anomalies                          │   │
│  │  • Join infra/app/deploy events across accounts                    │   │
│  │  • Compare to past incidents/deployments                           │   │
│  │  • Run pre-defined RCA scenarios (deployment, infra, dependency)   │   │
│  │  • Map probable cause to runbooks/fixes                            │   │
│  │                                                                     │   │
│  │  AI Provider Interface (pluggable):                                │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │   │
│  │  │ AWS Bedrock  │  │ OpenAI API   │  │ Self-Hosted  │             │   │
│  │  │ (Claude)     │  │ (GPT)        │  │ (Llama/etc)  │             │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘             │   │
│  │       Per-Agent-Type Selection (from policy config)                │   │
│  │                                                                     │   │
│  │  State Store: DynamoDB (agent state, audit logs, workflow history) │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────── Alert & UI Layer ───────────────────────┐       │
│  │                                                                 │       │
│  │  ┌────────────────────────────────────────────────────┐        │       │
│  │  │  Slack Bot (Lambda)                                │        │       │
│  │  │  • Webhook handler for incoming notifications      │        │       │
│  │  │  • Formats RCA payload with markdown              │        │       │
│  │  │  • Generates OpenSearch dashboard deep-link        │        │       │
│  │  │  • (Phase 1) Screenshot via headless browser      │        │       │
│  │  │  • Posts to #aiops-alerts channel                 │        │       │
│  │  └────────────────────────────────────────────────────┘        │       │
│  │                                                                 │       │
│  │  ┌────────────────────────────────────────────────────┐        │       │
│  │  │  OpenSearch Dashboards                             │        │       │
│  │  │  • Unified incident timeline (pre-built)           │        │       │
│  │  │  • Anomaly detection results (pre-built)           │        │       │
│  │  │  • RCA evidence explorer (pre-built)               │        │       │
│  │  │  • IAM-authenticated access (Platform/SRE only)    │        │       │
│  │  │  • Deep-linkable with query parameters             │        │       │
│  │  └────────────────────────────────────────────────────┘        │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                            │
│  ┌────────────────────── Configuration & IaC ─────────────────────┐       │
│  │                                                                 │       │
│  │  • Terraform modules (networking, IAM, data stores, compute)   │       │
│  │  • DynamoDB Policy Store (detection rules, AI provider config) │       │
│  │  • Secrets Manager (Slack webhook, API keys)                   │       │
│  │  • Parameter Store (runtime settings, feature flags)           │       │
│  └─────────────────────────────────────────────────────────────────┘       │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Data Ingestion (Per-Account → Central)

#### **Sources**
- **CloudWatch Logs**: Application logs, Lambda logs, VPC Flow Logs, ALB/NLB access logs
- **CloudWatch Metrics**: EC2, RDS, Lambda, EKS, custom application metrics
- **CloudTrail**: API activity, IAM/security events, configuration changes
- **EventBridge**: Deployment events, autoscaling notifications, health checks

#### **Transport Mechanisms**
- **Logs**: CloudWatch Logs Subscription Filter → Kinesis Data Firehose (cross-account)
- **Metrics**: CloudWatch cross-account observability (direct read access)
- **Events**: EventBridge cross-account event bus rules

#### **Cross-Account IAM**
- Member accounts assume `ObservabilityWriteRole` (write to Kinesis, EventBridge)
- Central account assumes `ObservabilityReadRole` per member (read CloudWatch metrics)
- Least privilege: deny destructive actions, restrict to observability APIs only

---

### 2. Storage (Central Observability Account, eu-central-1)

| Signal           | Storage                  | Retention          | Purpose                          |
|------------------|--------------------------|--------------------|----------------------------------|
| **Raw Logs**     | S3 (Glacier after 7d)    | 90 days (config)   | Audit, replay, cost optimization |
| **Indexed Logs** | OpenSearch Serverless    | 90 days (config)   | Search, visualization, alerting  |
| **Metrics**      | Timestream               | 30d hot, 90d cold  | Time-series queries, baselines   |
| **Events**       | DynamoDB                 | 90 days (TTL)      | Correlation, audit trail         |
| **Anomalies**    | DynamoDB                 | 90 days (TTL)      | RCA workflow input, dashboards   |
| **Agent State**  | DynamoDB                 | 30 days (TTL)      | Workflow orchestration, retries  |
| **Audit Logs**   | S3 + Athena              | 1 year             | AI prompt/response trail         |

**Normalization Schema** (canonical JSON):
```json
{
  "timestamp": "2026-02-14T10:00:00Z",
  "account_id": "123456789012",
  "region": "eu-central-1",
  "service": "api-gateway",
  "environment": "prod",
  "log_level": "ERROR",
  "message": "Database connection timeout",
  "deployment_version": "v2.3.1",
  "deployment_timestamp": "2026-02-14T09:15:00Z",
  "related_events": ["deploy-abc123", "autoscale-def456"]
}
```

**Enrichment Pipeline** (Lambda):
1. Parse raw logs into canonical schema
2. Extract account_id, region, service from log metadata
3. Lookup deployment version from DynamoDB (deployment event store)
4. Add environment tag from AWS Tags API
5. Write to OpenSearch + S3

---

### 3. Hybrid Anomaly Detection

#### **Statistical Detection** (SageMaker or Lambda)

**Algorithms**:
- **Seasonality Baseline**: STL decomposition (seasonal-trend decomposition)
- **Change-Point Detection**: PELT (Pruned Exact Linear Time) algorithm
- **Scoring**: Z-score with sliding window, EWMA (Exponentially Weighted Moving Average)

**Metrics Analyzed**:
- Error rate (errors per minute by service)
- Latency percentiles (p50, p95, p99)
- Request rate (traffic volume)
- Resource utilization (CPU, memory, disk I/O)

**Configuration** (per policy):
```yaml
detection:
  baseline_window: 7d        # Compare to last 7 days
  sensitivity: high          # low=4σ, medium=3σ, high=2σ
  min_deviation_pct: 50      # Ignore <50% changes
  cooldown_minutes: 30       # Suppress similar alerts for 30 min
```

**Output**: Anomaly object to DynamoDB
```json
{
  "anomaly_id": "anom-abc123",
  "timestamp": "2026-02-14T10:00:00Z",
  "signal": "p95_latency_ms",
  "service": "api-gateway",
  "account_id": "123456789012",
  "current_value": 1200,
  "baseline_value": 150,
  "deviation_pct": 700,
  "z_score": 5.2,
  "confidence": "high"
}
```

#### **Rule-Based Guardrails** (Lambda)

**Hard Thresholds**:
- Error rate > 5% for 5 consecutive minutes
- P95 latency > 2x baseline for 3 minutes
- Traffic drop > 80% within 10 minutes (canary failure)
- Security: IAM policy changes, S3 bucket public access

**Output**: Same anomaly object format (confidence = "rule_based")

---

### 4. Agentic Orchestration (Step Functions)

#### **Workflow Definition** (JSON state machine)

```json
{
  "StartAt": "DetectionAgent",
  "States": {
    "DetectionAgent": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:detection-agent",
      "Next": "CorrelationAgent"
    },
    "CorrelationAgent": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:correlation-agent",
      "Next": "HistoricalCompareAgent"
    },
    "HistoricalCompareAgent": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:historical-compare-agent",
      "Next": "RCAAgent"
    },
    "RCAAgent": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:rca-agent",
      "Next": "RecommendationAgent"
    },
    "RecommendationAgent": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:recommendation-agent",
      "Next": "FormatAlert"
    },
    "FormatAlert": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:slack-notifier",
      "End": true
    }
  }
}
```

#### **Agent Responsibilities**

| Agent                     | Input                           | Function                                                           | Output                          | AI Provider | MVP/Phase |
|---------------------------|---------------------------------|--------------------------------------------------------------------|---------------------------------|-------------|-----------|
| **Detection Agent**       | Anomaly object                  | Deduplicate, apply suppression rules, decide escalation           | Filtered anomaly                | None        | **MVP**   |
| **Correlation Agent**     | Filtered anomaly                | Join infra events, deployment events, related anomalies            | Enriched anomaly + context      | Bedrock (optional) | **MVP** |
| **Historical Compare**    | Enriched anomaly                | Find similar past incidents, compare current vs last deployment    | Similarity scores, past RCAs    | None (query) | **MVP**   |
| **RCA Agent**             | Anomaly + context + history     | Investigate pre-defined scenarios, generate hypothesis with confidence | Probable root cause + evidence | **Bedrock Claude** | **MVP** |
| **Recommendation Agent**  | RCA result                      | Map cause to runbooks, suggest next steps                          | Recommendations + links         | Bedrock (optional) | **MVP** |

#### **RCA Agent Scenarios** (Pre-Defined Investigations)

1. **Deployment Correlation**:
   - Query: Did a deployment happen in last 30 minutes?
   - Evidence: Deployment event, code diff, config changes
   - Hypothesis: "New deployment v2.3.1 introduced bug in API endpoint X"

2. **Infrastructure Change**:
   - Query: Did autoscaling, instance replacement, or AZ failure occur?
   - Evidence: EC2 events, ELB health checks, CloudWatch alarms
   - Hypothesis: "Instance i-abc123 became unhealthy, cascading load impact"

3. **Dependency Failure**:
   - Query: Is downstream service experiencing errors or latency?
   - Evidence: Correlated anomalies across services, API gateway metrics
   - Hypothesis: "Database service latency spike propagated to API layer"

4. **Resource Exhaustion**:
   - Query: Are CPU, memory, disk, or network limits hit?
   - Evidence: CloudWatch metrics, OOM logs, throttling errors
   - Hypothesis: "Memory leak in service caused OOMKilled events"

5. **Security/Access**:
   - Query: Did IAM policy, security group, or network ACL change?
   - Evidence: CloudTrail events, VPC flow logs
   - Hypothesis: "IAM role permission removed, blocking S3 access"

**AI Provider Call** (RCA Agent example):
```python
# Pseudo-code
context = {
    "anomaly": {...},
    "deployment_events": [...],
    "related_logs": [...],
    "similar_past_incidents": [...]
}

prompt = f"""
Analyze the following anomaly and determine probable root cause.

Anomaly: {context['anomaly']}
Recent Deployments: {context['deployment_events']}
Related Error Logs: {context['related_logs']}
Similar Past Incidents: {context['similar_past_incidents']}

Provide:
1. Probable root cause (1-2 sentences)
2. Confidence level (low/medium/high) with reasoning
3. Key evidence supporting hypothesis
4. Alternative explanations (if confidence < high)

Format as JSON.
"""

response = ai_provider.generate(
    agent_type="rca",  # selects provider from policy config
    prompt=prompt,
    max_tokens=500,
    temperature=0.2
)

# Log prompt + response to S3 for audit
audit_log(prompt, response)

return parse_rca_json(response)
```

---

### 5. AI Provider Abstraction Layer

#### **Interface Design**

**Unified Provider Interface**:
```python
class AIProvider(ABC):
    @abstractmethod
    def generate(self, agent_type: str, prompt: str, max_tokens: int, temperature: float) -> str:
        pass
    
    @abstractmethod
    def get_cost_per_token(self) -> float:
        pass
    
    @abstractmethod
    def get_model_info(self) -> dict:
        pass
```

**Concrete Implementations**:
- `BedrockProvider`: AWS Bedrock (Claude, Titan, etc.)
- `OpenAIProvider`: OpenAI API (GPT-4, GPT-5)
- `AnthropicProvider`: Anthropic API (Claude direct)
- `SelfHostedProvider`: SageMaker endpoint or ECS service (Llama, Mistral, etc.)

#### **Per-Agent-Type Selection** (from policy config)

**Configuration** (DynamoDB Policy Store):
```json
{
  "ai_provider_config": {
    "rca_agent": {
      "provider": "bedrock",
      "model": "anthropic.claude-3-sonnet",
      "temperature": 0.2,
      "max_tokens": 500,
      "cost_cap_per_day": 100.0
    },
    "correlation_agent": {
      "provider": "self-hosted",
      "endpoint": "https://llama-inference.internal.example.com",
      "model": "llama-3-70b",
      "temperature": 0.1,
      "max_tokens": 300,
      "cost_cap_per_day": 10.0
    },
    "recommendation_agent": {
      "provider": "bedrock",
      "model": "anthropic.claude-3-haiku",
      "temperature": 0.3,
      "max_tokens": 200,
      "cost_cap_per_day": 20.0
    }
  }
}
```

**Provider Selection Logic**:
```python
def get_provider_for_agent(agent_type: str) -> AIProvider:
    config = policy_store.get("ai_provider_config")[agent_type]
    
    if config["provider"] == "bedrock":
        return BedrockProvider(model=config["model"])
    elif config["provider"] == "self-hosted":
        return SelfHostedProvider(endpoint=config["endpoint"])
    elif config["provider"] == "openai":
        return OpenAIProvider(model=config["model"])
    else:
        raise ValueError(f"Unknown provider: {config['provider']}")
```

#### **Cost Control & Audit**

**Cost Tracking**:
- Every AI provider call logs: agent_type, model, input_tokens, output_tokens, cost, latency
- Aggregated in DynamoDB with hourly/daily partitions
- CloudWatch Alarm on daily spend > cost_cap_per_day

**Audit Logging** (S3 + Athena):
```json
{
  "timestamp": "2026-02-14T10:00:00Z",
  "agent_type": "rca_agent",
  "provider": "bedrock",
  "model": "claude-3-sonnet",
  "prompt": "<full prompt text>",
  "response": "<full response text>",
  "input_tokens": 1200,
  "output_tokens": 350,
  "cost_usd": 0.045,
  "latency_ms": 2300,
  "anomaly_id": "anom-abc123"
}
```

---

### 6. Slack Notification (Lambda)

#### **Alert Payload Format** (MVP)

**Slack Block Kit Structure**:
```json
{
  "channel": "#aiops-alerts",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "🚨 Latency Spike Detected: api-gateway (prod-account-123)"
      }
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*What Happened:*\nP95 latency increased from 150ms to 1200ms (700% deviation)"
        },
        {
          "type": "mrkdwn",
          "text": "*Confidence:*\nHigh (85%)"
        }
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Probable Root Cause:*\nDeployment v2.3.1 at 09:15 UTC introduced slow DB query in /users endpoint. Similar pattern observed in incident INC-2024-045."
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Key Evidence:*\n• Deployment timestamp correlates with spike start\n• Error logs show 'connection timeout' for user-db\n• Traffic to /users endpoint increased 3x post-deploy"
      }
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "View Dashboard"
          },
          "url": "https://opensearch.example.com/app/dashboards#/view/incident-abc123?time=2026-02-14T09:00:00Z_2026-02-14T10:30:00Z&service=api-gateway",
          "style": "primary"
        }
      ]
    }
  ]
}
```

**Deep-Link Generation**:
- OpenSearch dashboard URL with query parameters:
  - `time`: Pre-filtered to incident timeframe (±30 minutes)
  - `service`: Filter to affected service
  - `account_id`: Filter to affected account
  - `anomaly_id`: Direct link to anomaly details

#### **Screenshot Generation** (Phase 1)

**Approach**:
- Lambda with headless Chromium (Puppeteer or Playwright)
- Authenticate to OpenSearch, navigate to dashboard URL
- Take screenshot, upload to S3 signed URL
- Attach image URL to Slack message

**Implementation**:
```python
# Phase 1 enhancement
from playwright.sync_api import sync_playwright

def generate_dashboard_screenshot(dashboard_url: str) -> str:
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        
        # Authenticate (IAM session or API key)
        page.goto(dashboard_url)
        page.wait_for_load_state("networkidle")
        
        # Take screenshot
        screenshot_bytes = page.screenshot(full_page=False)
        
        # Upload to S3 with 24h expiry
        s3_url = upload_to_s3_with_expiry(screenshot_bytes, ttl_hours=24)
        
        browser.close()
        return s3_url

# Attach to Slack message
{
  "type": "image",
  "image_url": s3_url,
  "alt_text": "Dashboard screenshot for incident abc123"
}
```

---

### 7. OpenSearch Dashboards (Pre-Built)

#### **Dashboard 1: Unified Incident Timeline** (MVP)

**Visualizations**:
- **Timeline**: Horizontal bars showing anomalies, deployments, infra events across accounts
- **Filters**: Account, region, service, severity, time range
- **Drill-down**: Click anomaly → navigate to RCA Evidence Explorer

**Index Pattern**: `anomalies-*`, `events-*`

**Example Query** (pre-filtered via URL):
```json
{
  "query": {
    "bool": {
      "must": [
        {"range": {"timestamp": {"gte": "2026-02-14T09:00:00Z", "lte": "2026-02-14T10:30:00Z"}}},
        {"term": {"account_id": "123456789012"}},
        {"term": {"service": "api-gateway"}}
      ]
    }
  },
  "sort": [{"timestamp": "desc"}]
}
```

#### **Dashboard 2: Anomaly Detection Results** (MVP)

**Visualizations**:
- **Line chart**: Current metric vs baseline (e.g., latency over time)
- **Heatmap**: Anomaly density by service/account
- **Table**: Anomaly details (timestamp, metric, deviation, confidence)

**Filters**: Confidence level, deviation %, service

#### **Dashboard 3: RCA Evidence Explorer** (MVP)

**Layout** (linked from Slack alert):
- **Top Panel**: RCA summary, confidence, probable cause
- **Left Panel**: Related logs (filtered to incident timeframe)
- **Center Panel**: Metrics visualization (before/during/after incident)
- **Right Panel**: Events timeline (deployments, autoscaling, alerts)

**Deep-Link Example**:
```
https://opensearch.example.com/app/dashboards#/view/rca-explorer
  ?anomaly_id=anom-abc123
  &time=2026-02-14T09:00:00Z_2026-02-14T10:30:00Z
  &service=api-gateway
```

OpenSearch automatically applies filters to all panels based on URL parameters.

---

## Deployment Architecture (MVP)

### **Infrastructure Components** (Terraform Modules)

#### **Module: Networking**
- VPC with private subnets (no public internet access for compute)
- VPC Endpoints for AWS services (S3, DynamoDB, Secrets Manager, SageMaker)
- Security groups with least privilege

#### **Module: IAM Roles**
- `ObservabilityWriteRole` (member accounts) → write to Kinesis/EventBridge
- `ObservabilityReadRole` (central account) → read CloudWatch metrics from members
- `LambdaExecutionRole` → read/write to DynamoDB, S3, OpenSearch, invoke Step Functions
- `StepFunctionsExecutionRole` → invoke Lambda, write to DynamoDB

#### **Module: Data Stores**
- S3 buckets (raw logs, audit logs) with lifecycle policies
- OpenSearch Serverless collection with IAM authentication
- DynamoDB tables: anomalies, events, policy_store, agent_state, audit_logs
- Timestream database for metrics

#### **Module: Compute**
- Lambda functions (normalization, detection, agents, Slack notifier)
- Step Functions state machine (agentic orchestration)
- (Optional) SageMaker endpoint for self-hosted LLM

#### **Module: Observability**
- CloudWatch Logs for Lambda
- CloudWatch Alarms for cost caps, error rates
- X-Ray tracing for Step Functions workflows

### **Deployment Steps** (MVP)

**Phase: Setup Central Account**
```bash
# 1. Deploy networking and IAM
terraform apply -target=module.networking -target=module.iam

# 2. Deploy data stores
terraform apply -target=module.data_stores

# 3. Deploy compute (Lambda, Step Functions)
terraform apply -target=module.compute

# 4. Deploy OpenSearch dashboards (import saved objects)
./scripts/import-opensearch-dashboards.sh

# 5. Configure Slack webhook
aws secretsmanager create-secret \
  --name aiops/slack-webhook \
  --secret-string '{"url": "https://hooks.slack.com/services/..."}'
```

**Phase: Configure Member Accounts**
```bash
# Deploy cross-account IAM role per member account
cd member-account-setup
terraform apply \
  -var="central_account_id=123456789012" \
  -var="account_id=987654321098"

# Deploy CloudWatch Logs subscription filters
./scripts/setup-log-subscriptions.sh --account-id 987654321098
```

**Phase: Load Detection Policies**
```bash
# Upload default policies to DynamoDB
./scripts/load-policies.sh --file policies/default-policies.yaml
```

---

## Data Flow Example (End-to-End)

**Scenario**: API Gateway latency spike caused by slow database query

### **Step 1: Ingestion** (T+0 seconds)
- API Gateway logs show 500ms+ response times
- CloudWatch Logs → Subscription Filter → Kinesis Firehose → S3 + Lambda

### **Step 2: Normalization** (T+5 seconds)
- Lambda parses logs, enriches with deployment metadata
- Writes to OpenSearch: `{"timestamp": "...", "service": "api-gateway", "p95_latency_ms": 1200, ...}`

### **Step 3: Detection** (T+30 seconds)
- Statistical detector queries Timestream: "p95_latency_ms for api-gateway, last 7 days"
- Baseline = 150ms, current = 1200ms, z-score = 5.2 → ANOMALY
- Writes to DynamoDB anomalies table, triggers Step Functions

### **Step 4: Agentic Workflow** (T+30s to T+2min)
1. **Detection Agent**: Checks for duplicate anomalies (none found), passes through
2. **Correlation Agent**: Queries events table, finds deployment v2.3.1 at T-15min
3. **Historical Compare**: Searches past incidents, finds similar latency spike (INC-2024-045)
4. **RCA Agent**: Calls Bedrock Claude with context:
   - Prompt: "Anomaly: latency spike. Recent deployment: v2.3.1. Similar incident: INC-2024-045 (slow DB query). Analyze."
   - Response: "Probable cause: New deployment introduced slow query. Confidence: High (85%). Evidence: Deployment timestamp aligns with spike. Error logs show DB timeouts."
5. **Recommendation Agent**: Maps to runbook: "Rollback deployment or optimize query"

### **Step 5: Alert** (T+2min)
- Slack notifier formats payload (RCA summary + OpenSearch link)
- Posts to #aiops-alerts
- Engineer clicks link, lands on pre-filtered dashboard showing logs, metrics, deployment event

### **Step 6: Investigation** (T+3min)
- Engineer reviews OpenSearch dashboard
- Confirms RCA hypothesis by drilling into slow query logs
- Executes rollback or query optimization

**Total Time: Anomaly detection → Alert in engineer's hands = <2 minutes**

---

## Phased Deployment Strategy

### **MVP** (Weeks 1-8)
**Goal**: End-to-end pipeline with basic alerting.

| Week | Deliverable |
|------|-------------|
| 1-2  | Infrastructure setup (Terraform, IAM, S3, DynamoDB, OpenSearch) |
| 3-4  | Ingestion pipeline (CloudWatch → Kinesis → Lambda → OpenSearch) |
| 5    | Statistical anomaly detection (Lambda + Timestream queries) |
| 6    | Step Functions orchestration + Detection/Correlation agents |
| 7    | RCA Agent with Bedrock Claude integration |
| 8    | Slack notifier + 3 OpenSearch dashboards |

**Success Criteria**:
- ✅ Ingest logs from 5 test accounts
- ✅ Detect 1 synthetic anomaly (injected latency spike)
- ✅ Generate RCA with confidence score
- ✅ Deliver Slack alert with OpenSearch link

### **Phase 1** (Weeks 9-12)
**Goal**: Production-ready with enhanced observability.

| Week | Deliverable |
|------|-------------|
| 9    | Screenshot generation for Slack alerts |
| 10   | Multi-account rollout (20+ accounts) |
| 11   | Cost/usage dashboard for AI providers |
| 12   | Detection policy effectiveness metrics |

### **Phase 2** (Weeks 13-20)
**Goal**: Interactive engagement and smart routing.

| Week | Deliverable |
|------|-------------|
| 13-14 | Slack bot Q&A (natural language queries) |
| 15    | Interactive Slack actions (acknowledge, snooze) |
| 16-17 | Runbook integration and execution triggers |
| 18    | Smart alert routing (per-account channels) |
| 19    | Feedback loop (👍/👎 on RCA quality) |
| 20    | Model retraining based on feedback |

---

## Operational Considerations

### **Monitoring & Alerting**
- **Pipeline health**: CloudWatch alarms on Lambda errors, Step Functions failures
- **Data lag**: Alert if OpenSearch indexing lag > 5 minutes
- **Cost**: Daily budget alerts on AI provider spend, S3/OpenSearch usage
- **RCA accuracy**: Track confidence vs engineer validation (Phase 2 feedback loop)

### **Disaster Recovery**
- **Data loss**: S3 cross-region replication for raw logs (optional for Phase 2)
- **Control plane**: Terraform state in S3 with versioning, infrastructure reproducible in <1 hour
- **OpenSearch**: Automated snapshots to S3 every 24 hours

### **Security**
- **Encryption**: S3/DynamoDB encryption at rest (KMS), TLS in transit
- **Access control**: IAM roles only, no long-lived credentials
- **Audit trail**: All AI prompts/responses logged to S3 for compliance

### **Cost Optimization**
- **Compute**: Lambda scales to zero, Step Functions pay-per-transition
- **Storage**: S3 Intelligent-Tiering for raw logs, OpenSearch Serverless pay-per-use
- **AI providers**: Per-agent cost caps, option to use self-hosted LLMs for high-volume tasks

---

## Technology Stack Summary

| Layer              | Technology                          | Rationale                                       |
|--------------------|-------------------------------------|-------------------------------------------------|
| **Ingestion**      | Kinesis Firehose, EventBridge       | Managed, scalable, cross-account support        |
| **Storage**        | S3, OpenSearch Serverless, Timestream, DynamoDB | Purpose-built for logs, metrics, events        |
| **Compute**        | Lambda, Step Functions              | Serverless, cost-effective, zero ops overhead   |
| **Detection**      | Lambda (rules), SageMaker (ML)      | Flexible, supports custom algorithms            |
| **Orchestration**  | Step Functions                      | Visual workflows, retries, auditability         |
| **AI Provider**    | AWS Bedrock (MVP), pluggable        | Multi-model support, easy to extend             |
| **Dashboards**     | OpenSearch Dashboards               | Built-in, powerful, no custom UI needed         |
| **Notifications**  | Slack API (Lambda)                  | Simple webhook, rich formatting                 |
| **IaC**            | Terraform                           | Reproducible, version-controlled                |
| **Region**         | eu-central-1 (single region MVP)    | Customer preference, expand in Phase 2          |

---

## Open Questions & Future Enhancements

### **MVP Open Questions**
1. **Screenshot tool**: Use Puppeteer (Node.js Lambda) or Playwright (containerized Lambda)?
2. **Self-hosted LLM**: Should MVP include SageMaker endpoint setup, or defer to Phase 1?
3. **Deployment version tracking**: How to extract version from logs if not explicitly tagged?

### **Future Enhancements** (Beyond Phase 2)
- **Multi-region**: Active-passive control plane for disaster recovery
- **Autonomous remediation**: Rollback, scaling, config changes (Phase 3)
- **Cost attribution**: Per-service/team AI provider billing
- **Advanced ML**: Reinforcement learning for detection policy tuning
- **External integrations**: Jira/ServiceNow ticketing, PagerDuty escalation policies

