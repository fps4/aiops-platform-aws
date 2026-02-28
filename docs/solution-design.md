# Solution Design

## Architecture Overview

The AIOps Platform is a **centralized observability control plane** that ingests signals from multiple AWS accounts, applies hybrid anomaly detection, orchestrates agentic RCA workflows, and delivers proactive alerts via Slack with Grafana dashboard integration.

**Architecture Principles**:
- **AWS-native**: Leverage managed services to minimize operational overhead
- **Serverless-first**: Lambda, Fargate, and managed data stores — right tool per workload
- **Deterministic orchestration**: Workflows are replayable, auditable, and transparent
- **Pluggable AI**: Support multiple AI providers via unified abstraction layer
- **Multi-account by design**: Central observability account with cross-account read roles

**Architecture Decisions**:
- [ADR-001: Observability Storage and Visualization Stack](decisions/001-observability-storage-and-visualization.md) — rationale for ClickHouse + Grafana (plain EC2, systemd) over OpenSearch Serverless; addendum documents migration from original ECS/Fargate design

---

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AWS Accounts (Member)                            │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │
│  │  CloudWatch    │  │  CloudTrail    │  │  ALB/RDS/EKS   │            │
│  │  Logs/Metrics  │  │  Events        │  │  Lambda Logs   │            │
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
                    (Kinesis Firehose)
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
│  │                         │ ClickHouse    │◀─── Analytics/Viz    │        │
│  │                         │ (EC2/systemd) │     Logs + Metrics   │        │
│  │                         └───────────────┘                      │        │
│  │                                                                │        │
│  │                         ┌───────────────┐                      │        │
│  │                         │ DynamoDB      │◀─── Events/State     │        │
│  │                         │ Tables        │                      │        │
│  │                         └───────────────┘                      │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                                                            │
│  ┌───────────────────── Detection Layer ──────────────────────────┐       │
│  │                                                                 │       │
│  │  ┌─────────────────────────────────────────────────────┐       │       │
│  │  │  Statistical Detectors (Fargate Scheduled Task)     │       │       │
│  │  │  • Runs every 5 min via EventBridge Scheduler       │       │       │
│  │  │  • Queries ClickHouse for 7-day baselines           │       │       │
│  │  │  • STL decomposition, PELT, Z-score/EWMA           │       │       │
│  │  │  • Iterates all services/metrics in single run      │       │       │
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
│  ┌────────── Agentic Orchestration (Orchestrator Lambda) ────────────┐   │
│  │                                                                     │   │
│  │  Triggered by: DynamoDB Stream on anomalies table                 │   │
│  │                                                                     │   │
│  │  Pipeline (sequential in single Lambda invocation):               │   │
│  │  Anomaly → [Detection Agent] → [Correlation Agent] →               │   │
│  │            [Historical Compare] → [RCA Agent] →                    │   │
│  │            [Recommendation Agent] → Slack Alert                    │   │
│  │                                                                     │   │
│  │  Each agent = Python module with run() interface:                 │   │
│  │  • detection_agent.run()    — deduplicate, suppress, escalate     │   │
│  │  • correlation_agent.run()  — join infra/app/deploy events        │   │
│  │  • historical_agent.run()   — compare to past incidents           │   │
│  │  • rca_agent.run()          — RCA via Bedrock (pluggable)         │   │
│  │  • recommendation_agent.run() — map cause to runbooks             │   │
│  │                                                                     │   │
│  │  AI Provider Interface (pluggable):                                │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │   │
│  │  │ AWS Bedrock  │  │ OpenAI API   │  │ Self-Hosted  │             │   │
│  │  │ (Claude)     │  │ (GPT)        │  │ (Llama/etc)  │             │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘             │   │
│  │       Per-Agent-Type Selection (from policy config)                │   │
│  │                                                                     │   │
│  │  Audit: DynamoDB (agent state) + S3 (prompt/response logs)        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────── Alert & UI Layer ───────────────────────┐       │
│  │                                                                 │       │
│  │  ┌────────────────────────────────────────────────────┐        │       │
│  │  │  Slack Bot (Lambda)                                │        │       │
│  │  │  • Webhook handler for incoming notifications      │        │       │
│  │  │  • Formats RCA payload with markdown              │        │       │
│  │  │  • Generates Grafana dashboard deep-link           │        │       │
│  │  │  • (Phase 1) Screenshot via headless browser      │        │       │
│  │  │  • Posts to #aiops-alerts channel                 │        │       │
│  │  └────────────────────────────────────────────────────┘        │       │
│  │                                                                 │       │
│  │  ┌────────────────────────────────────────────────────┐        │       │
│  │  │  Grafana (EC2/systemd, SSM port-forward)           │        │       │
│  │  │  • Unified incident timeline (pre-built)           │        │       │
│  │  │  • Anomaly detection results (pre-built)           │        │       │
│  │  │  • RCA evidence explorer (pre-built)               │        │       │
│  │  │  • ClickHouse datasource (SQL queries)             │        │       │
│  │  │  • Deep-linkable with variable + time params       │        │       │
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

## Component Overview

| Component | Description | Detail |
|---|---|---|
| **Data Ingestion** | CloudWatch Logs + CloudTrail → Kinesis Firehose → Lambda normalizer | [→ components/01-data-ingestion.md](components/01-data-ingestion.md) |
| **Storage** | ClickHouse (EC2/systemd) for logs/metrics; DynamoDB for events/state; S3 for raw logs | [→ components/02-storage.md](components/02-storage.md) |
| **Anomaly Detection** | Fargate scheduled task (STL, PELT, Z-score) + Lambda rule-based guardrails | [→ components/03-anomaly-detection.md](components/03-anomaly-detection.md) |
| **Agentic Orchestration** | Orchestrator Lambda triggered by DynamoDB Stream: 5-agent pipeline ending in Slack alert | [→ components/04-agentic-orchestration.md](components/04-agentic-orchestration.md) |
| **AI Provider** | Pluggable abstraction over Bedrock, OpenAI, self-hosted; per-agent model + temperature config | [→ components/05-ai-provider.md](components/05-ai-provider.md) |
| **Slack Notification** | Block Kit alerts with RCA summary and Grafana deep-links; Phase 1 screenshot generation | [→ components/06-slack-notification.md](components/06-slack-notification.md) |
| **Grafana Dashboards** | 3 pre-built dashboards (Incident Timeline, Anomaly Results, RCA Explorer) backed by ClickHouse SQL | [→ components/07-grafana-dashboards.md](components/07-grafana-dashboards.md) |
| **Deployment** | Terraform modules; ClickHouse + Grafana on plain EC2; Fargate for statistical detector | [→ components/08-deployment-architecture.md](components/08-deployment-architecture.md) |
| **Operations** | Monitoring, disaster recovery, security, cost optimization | [→ components/09-operational-considerations.md](components/09-operational-considerations.md) |

---

## Data Flow (Summary)

> Full step-by-step walkthrough with example SQL and agent outputs: [→ components/10-data-flow-example.md](components/10-data-flow-example.md)

```
Member logs/events → Kinesis Firehose → Lambda normalizer → S3 (raw) + ClickHouse
                                                                        ↓
                                         Fargate statistical detector (every 5 min)
                                         Lambda rule-based detector    (every 5 min)
                                                                        ↓
                                                       DynamoDB anomalies table
                                                                        ↓ (Stream)
                                                       Orchestrator Lambda
                              Detection → Correlation → Historical → RCA → Recommendation
                                                                        ↓
                                                       Slack alert + Grafana deep-link
```

**Total latency: anomaly → alert in engineer's hands < 7 minutes**
(up to 5 min detection interval + ~2 min agentic pipeline)

---

## Technology Stack

| Layer              | Technology                             | Rationale                                                              |
|--------------------|----------------------------------------|------------------------------------------------------------------------|
| **Ingestion**      | Kinesis Firehose                       | Managed, scalable, cross-account support                               |
| **Storage**        | S3, ClickHouse (EC2/systemd), DynamoDB | Logs + metrics in ClickHouse (SQL, columnar); events/state in DynamoDB |
| **Compute**        | Lambda, Fargate, EC2                   | Lambda for event-driven; Fargate for stateless scheduled; EC2 for stateful ClickHouse + Grafana |
| **Detection**      | Fargate (statistical), Lambda (rules)  | Fargate for heavy ML libs; Lambda for lightweight thresholds           |
| **Orchestration**  | Orchestrator Lambda + DynamoDB Stream  | Simple linear pipeline, no extra service overhead                      |
| **AI Provider**    | AWS Bedrock (MVP), pluggable           | Multi-model support, easy to extend                                    |
| **Dashboards**     | Grafana (EC2/systemd) + ClickHouse datasource | Purpose-built visualization; SQL queries align with Phase 2 NL chat agent |
| **Notifications**  | Slack API (Lambda)                     | Simple webhook, rich formatting                                        |
| **IaC**            | Terraform                              | Reproducible, version-controlled                                       |
| **Region**         | eu-central-1 (single region MVP)       | Customer preference, expand in Phase 2                                 |

---

## Phased Deployment Strategy

### MVP (Weeks 1–8)
**Goal**: End-to-end pipeline with basic alerting.

| Week | Deliverable |
|------|-------------|
| 1–2  | Infrastructure setup (Terraform, IAM, S3, DynamoDB, ClickHouse on EC2) |
| 3–4  | Ingestion pipeline (CloudWatch → Kinesis → Lambda → ClickHouse) |
| 5    | Statistical anomaly detection (Fargate scheduled task + ClickHouse SQL queries) |
| 6    | Orchestrator Lambda + Detection/Correlation agents |
| 7    | RCA Agent with Bedrock Claude integration |
| 8    | Slack notifier + 3 Grafana dashboards (ClickHouse datasource) |

**Success Criteria**:
- ✅ Ingest logs from 5 test accounts
- ✅ Detect 1 synthetic anomaly (injected latency spike)
- ✅ Generate RCA with confidence score
- ✅ Deliver Slack alert with Grafana deep-link

### Phase 1 (Weeks 9–12)
**Goal**: Production-ready with enhanced observability.

| Week | Deliverable |
|------|-------------|
| 9    | Screenshot generation for Slack alerts |
| 10   | Multi-account rollout (20+ accounts) |
| 11   | Cost/usage dashboard for AI providers |
| 12   | Detection policy effectiveness metrics |

### Phase 2 (Weeks 13–20)
**Goal**: Interactive engagement and smart routing.

| Week | Deliverable |
|------|-------------|
| 13–14 | Slack bot Q&A (natural language queries over ClickHouse SQL) |
| 15    | Interactive Slack actions (acknowledge, snooze) |
| 16–17 | Runbook integration and execution triggers |
| 18    | Smart alert routing (per-account channels) |
| 19    | Feedback loop (👍/👎 on RCA quality) |
| 20    | Model retraining based on feedback |

---

## Open Questions & Future Enhancements

### MVP Open Questions
1. **Screenshot tool**: Use Puppeteer (Node.js Lambda) or Playwright (containerized Lambda)?
2. **Self-hosted LLM**: Should MVP include SageMaker endpoint setup, or defer to Phase 1?
3. **Deployment version tracking**: How to extract version from logs if not explicitly tagged?

### Future Enhancements (Beyond Phase 2)
- **Multi-region**: Active-passive control plane for disaster recovery
- **Autonomous remediation**: Rollback, scaling, config changes (Phase 3)
- **Cost attribution**: Per-service/team AI provider billing
- **Advanced ML**: Reinforcement learning for detection policy tuning
- **External integrations**: Jira/ServiceNow ticketing, PagerDuty escalation policies
