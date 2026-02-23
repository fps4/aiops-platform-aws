# ADR-001: Observability Storage and Visualization Stack

**Status**: Accepted
**Date**: 2026-02-22
**Deciders**: Platform team

---

## Context

The original solution design used **OpenSearch Serverless** for both indexed log/metric storage and dashboards (OpenSearch Dashboards). During design review, two concerns were raised:

1. **Cost**: OpenSearch Serverless has a minimum of 2 OCUs at ~$175/OCU/month (~$350+/mo), making it expensive for small-to-medium workloads.
2. **Product fit**: OpenSearch Dashboards felt like a secondary concern in the OpenSearch ecosystem — not a first-class visualization tool. For a platform being open-sourced as a reference architecture, a more purpose-built visualization layer was preferred.

The decision was made to replace OpenSearch with a dedicated storage backend and a proper visualization tool. Two options were evaluated.

---

## Options Considered

### Option A: ClickHouse on EC2 (ECS) + Grafana on Fargate

ClickHouse is a columnar OLAP database optimized for high-speed analytics over logs and time-series metrics. It stores logs and metrics in a single system with a SQL interface. Grafana connects to it natively.

ClickHouse requires persistent local storage and cannot run on Fargate without EBS (which is newer, less battle-tested for stateful workloads). It runs as an ECS task on an EC2 instance.

### Option B: Loki + VictoriaMetrics + Grafana on Fargate (fully serverless)

Loki (log aggregation, S3-backed) and VictoriaMetrics (time-series metrics, EFS-backed) are purpose-built, lightweight systems with native Grafana datasource support. Both run on Fargate with no EC2 to manage.

---

## Cost Analysis

All prices in eu-central-1, February 2026.

### Option A — ClickHouse on EC2 + Grafana on Fargate

**EC2 for ClickHouse**

| Instance | On-demand | 1-yr reserved | RAM | Notes |
|---|---|---|---|---|
| t3.medium | $33.87/mo | ~$21/mo | 4GB | Minimum floor, dev/low volume |
| t3.large | $67.74/mo | ~$42/mo | 8GB | Recommended for production |

ECS control plane (EC2 launch type) = $0. EBS gp3 100GB = $9.52/mo.

**Fargate services**

| Service | vCPU | Memory | Schedule | Cost/mo |
|---|---|---|---|---|
| Grafana | 0.25 | 0.5GB | 24/7 | $9.01 |
| Statistical detector | 0.25 | 0.5GB | 1.5 min / 5 min | $2.67 |

**Supporting infrastructure**

| Component | Cost/mo | Notes |
|---|---|---|
| ALB (Grafana public access) | $19 | $0.0252/hr fixed + minimal LCU |
| Lambda functions | $1–5 | Pay per invocation |
| DynamoDB | $3–8 | On-demand |
| Kinesis Firehose | $1–5 | $0.029/GB ingested |
| S3 | $3–6 | Raw logs + ClickHouse backups + audit |
| CloudWatch | $5–10 | Logs + alarms |
| Secrets Manager | $1 | |
| Bedrock (Claude Sonnet) | $15–40 | ~50 RCA calls/day at moderate volume† |

†~50 RCA calls/day × 1,500 input + 500 output tokens × 30 days ≈ $18–25/mo.

**Monthly total — Option A**

| Scenario | EC2 | EBS | Fargate | ALB | Other infra | Bedrock | **Total** |
|---|---|---|---|---|---|---|---|
| t3.medium, on-demand | $34 | $10 | $12 | $19 | $14–35 | $15–40 | **$104–150** |
| t3.large, on-demand | $68 | $10 | $12 | $19 | $14–35 | $15–40 | **$138–184** |
| t3.large, 1-yr reserved | $42 | $10 | $12 | $19 | $14–35 | $15–40 | **$112–158** |

---

### Option B — Loki + VictoriaMetrics + Grafana on Fargate

**Fargate services**

| Service | vCPU | Memory | Schedule | Cost/mo |
|---|---|---|---|---|
| Loki | 0.25 | 0.5GB | 24/7 | $9.01 |
| VictoriaMetrics | 0.25 | 0.5GB | 24/7 | $9.01 |
| Grafana | 0.25 | 0.5GB | 24/7 | $9.01 |
| Statistical detector | 0.25 | 0.5GB | 1.5 min / 5 min | $2.67 |

**Storage**

| Component | Cost/mo | Notes |
|---|---|---|
| S3 (Loki chunks + index) | $2–4 | Compressed log storage |
| EFS (VictoriaMetrics data + Grafana SQLite) | $1–3 | Small datasets |

Supporting infrastructure same as Option A.

**Monthly total — Option B**

| Scenario | Fargate (all) | Storage | ALB | Other infra | Bedrock | **Total** |
|---|---|---|---|---|---|---|
| All on-demand | $30 | $4–7 | $19 | $14–35 | $15–40 | **$82–131** |

---

### Cost comparison

| Component | Option A (ClickHouse) | Option B (Loki + VictoriaMetrics) |
|---|---|---|
| Data store compute | $34–68 (EC2) | $18 (3× Fargate) |
| Data store storage | $10 (EBS) | $4–6 (S3 + EFS) |
| ALB | $19 | $19 |
| Everything else | same | same |
| **Monthly delta** | +$20–50 | — |

---

## Decision

**Option A: ClickHouse on EC2 (ECS) + Grafana on Fargate.**

While Option B is ~$20–50/month cheaper, ClickHouse was chosen for the following reasons:

1. **Unified query interface**: ClickHouse stores logs and metrics in a single system with a SQL interface. Option B requires two separate query languages (LogQL for Loki, MetricsQL for VictoriaMetrics) with no cross-system joins.

2. **Phase 2 NL chat agent**: The product roadmap includes a natural language Q&A agent over observability data. LLMs generate SQL reliably and accurately; generating correct LogQL and MetricsQL is significantly harder and more error-prone. ClickHouse makes this feature substantially easier to implement.

3. **Log analytics power**: The product requires LLM-assisted semantic signals — detecting new error patterns and rare log messages. This involves `GROUP BY`, frequency counting, and pattern matching over log data. ClickHouse's columnar engine handles this far better than Loki's LogQL.

4. **Single system to operate**: One database instead of two reduces operational complexity, even though it requires an EC2 instance.

5. **Cost is acceptable**: At t3.large + 1-year reserved (~$112–158/mo all-in), the cost is reasonable for a commercial product. The $20–50/mo delta vs Option B is justified by the capabilities gained.

**Deployment**: ClickHouse runs as an ECS task on an EC2 ECS cluster (t3.large, 1-year reserved). Grafana and the statistical detector run on Fargate. All Lambda functions remain unchanged.

---

## Consequences

### Architecture changes from original OpenSearch design

| Layer | Before | After |
|---|---|---|
| Log storage | OpenSearch Serverless | ClickHouse (ECS EC2) |
| Metric storage | OpenSearch Serverless | ClickHouse (ECS EC2) |
| Visualization | OpenSearch Dashboards | Grafana (Fargate) |
| Log query API | OpenSearch DSL | ClickHouse SQL over HTTP |
| Metric query API | OpenSearch DSL | ClickHouse SQL over HTTP |
| Dashboard deep-links | OpenSearch Dashboards URLs | Grafana URLs with time/variable params |

### What stays the same

- All Lambda functions (log-normalizer, rule-detection, orchestrator, Slack notifier)
- Kinesis Firehose ingestion pipeline
- S3 for raw logs and audit trail
- DynamoDB tables (anomalies, events, policy_store, agent_state)
- Bedrock AI provider and agent pipeline

### Required changes

- **log-normalizer Lambda**: writes to ClickHouse HTTP API instead of OpenSearch bulk API
- **Statistical detector (Fargate)**: queries ClickHouse SQL instead of OpenSearch aggregations
- **Orchestrator agents** (correlation, historical compare): query ClickHouse instead of OpenSearch
- **Slack notifier**: generates Grafana deep-links instead of OpenSearch Dashboard URLs
- **Terraform**: replace OpenSearch Serverless module with ECS EC2 cluster + ClickHouse task definition + EBS volume
- **Grafana dashboards**: rebuild 3 pre-built dashboards (Incident Timeline, Anomaly Detection Results, RCA Evidence Explorer) using ClickHouse datasource

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| EC2 instance is a single point of failure | ECS task auto-restart; ClickHouse data on EBS survives restarts; 1-yr reserved instance reduces cost of HA addition later |
| ClickHouse schema migrations | Version-controlled schema in Terraform; migration scripts in `scripts/` |
| Log-normalizer must stay storage-agnostic | Push endpoint configured via SSM Parameter Store, not hardcoded |
