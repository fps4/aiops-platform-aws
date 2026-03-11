# Technical Architecture

## Architecture summary

The platform implements a centralized control plane in **eu-central-1**. It ingests AWS signals across accounts, stores normalized data, runs hybrid detection, executes agentic RCA orchestration, and emits Slack alerts linked to Grafana dashboards.

## Design principles

- AWS-native, serverless-first where practical
- Deterministic orchestration and auditable decisions
- Pluggable AI provider abstraction
- Modular components with clear boundaries

## High-level flow

```
Member Accounts
  -> CloudWatch Logs / CloudTrail
  -> Subscription Filters
  -> Kinesis Firehose
  -> Normalization Lambda
  -> S3 (raw) + ClickHouse (analytics)
  -> Detection layer (Fargate statistical + Lambda rule-based)
  -> DynamoDB anomalies table + stream
  -> Orchestrator Lambda (5-agent pipeline)
  -> Slack notifier + Grafana deep-link
```

## Runtime components

### Data plane

- **Ingestion**: CloudWatch Logs + CloudTrail, centralized via Kinesis Firehose
- **Normalization**: Lambda transforms records to canonical schema
- **Storage**:
  - S3 for raw immutable records
  - ClickHouse for analytical queries and dashboards
  - DynamoDB for anomalies, policy, and workflow state

### Detection plane

- **Statistical detector**: scheduled Fargate task querying ClickHouse baselines
- **Rule-based detector**: Lambda guardrails for deterministic thresholds
- **Output**: structured anomalies written to DynamoDB

### Orchestration plane

- **Trigger**: DynamoDB stream on anomalies table
- **Engine**: orchestrator Lambda running sequential agents:
  - Detection
  - Correlation
  - Historical comparison
  - RCA
  - Recommendation
- **Auditability**: agent state + AI prompt/response logging

### Presentation plane

- **Notifications**: Slack Lambda posts rich incident summaries
- **Visual analytics**: Grafana dashboards backed by ClickHouse datasource
- **Investigation UX**: deep-links with pre-applied scope and time filters

### Telemetry plane

- **Instrumentation standard**: OpenTelemetry in platform and client/application services.
- **Trace backend (Phase 1)**: AWS X-Ray via ADOT/OTEL exporters.
- **Metrics backend (Phase 1)**: CloudWatch metrics and alarms (optional AMP for Prometheus-style workloads).
- **Propagation**: trace context and correlation attributes (`anomaly_id`, `workflow_id`, `account_id`, `service`) across async boundaries.

## AI provider architecture

- Unified interface for model invocation by agent type.
- Default MVP provider path is Bedrock, with extensibility for OpenAI and self-hosted models.
- Per-agent model/temperature policies and usage auditing are first-class concerns.

## Configuration and deployment

- Terraform modules under `terraform/modules/*`
- Environment definitions under `terraform/environments/*`
- Runtime settings via policy store and parameter management

## End-to-end incident flow example

**Scenario**: API Gateway latency spike caused by a slow database query introduced by a deployment.

1. **Ingestion (T+0s)**: CloudWatch Logs stream through subscription filters into Firehose and the normalization Lambda.
2. **Normalization (T+5s)**: records are enriched and written to S3 (raw) and ClickHouse (indexed).
3. **Detection (<=5 min cadence)**: statistical detector compares baseline vs current (`p95` rises from 150ms to 1200ms), writes anomaly to DynamoDB.
4. **Agentic pipeline (T+30s to T+2min)**:
   - Detection agent suppresses duplicates
   - Correlation agent links deployment event
   - Historical comparison finds similar past incident
   - RCA agent produces probable cause and confidence
   - Recommendation agent maps to rollback/query optimization runbook
5. **Notification (T+2min)**: Slack message with evidence summary and Grafana deep-link is posted.
6. **Investigation (T+3min)**: responder validates evidence and executes mitigation.

Typical latency from anomaly formation to actionable alert is under 7 minutes.

## Component deep dives

- [components/01-data-ingestion.md](components/01-data-ingestion.md)
- [components/02-storage.md](components/02-storage.md)
- [components/03-anomaly-detection.md](components/03-anomaly-detection.md)
- [components/04-agentic-orchestration.md](components/04-agentic-orchestration.md)
- [components/05-ai-provider.md](components/05-ai-provider.md)
- [components/06-slack-notification.md](components/06-slack-notification.md)
- [components/07-grafana-dashboards.md](components/07-grafana-dashboards.md)
