# Executive Overview

## Observe - Engage - Automate

The AIOps Agentic System is an AWS-native, multi-account observability control plane that detects anomalies, orchestrates AI-assisted root-cause analysis (RCA), and delivers actionable alerts to engineering teams.

Phase 1 focuses on **Observe + Engage**. Autonomous remediation remains out of scope.

## What the product does

- Centralizes logs, metrics, and events from multiple AWS accounts into one observability account.
- Uses hybrid anomaly detection (statistical + rule-based), with LLMs as explainers and correlators.
- Runs a deterministic agent pipeline to produce RCA, confidence scores, and recommended next steps.
- Notifies teams in Slack with deep-links to Grafana dashboards for rapid investigation.

## Who it is for

- **Platform/SRE teams** who operate AWS estates, tune detection policies, and respond to incidents.
- **Product Engineering teams** who own application services, instrument telemetry, and partner on incident triage/remediation.
- **Open-source contributors** extending detection logic, orchestration agents, and integrations.

## Product tenets

- **AWS-native first**: managed AWS services where practical.
- **Deterministic first**: LLMs augment explanations, not core detection logic.
- **Evidence over intuition**: every conclusion includes traceable signals and confidence.
- **Pluggable AI providers**: commercial and self-hosted models behind one interface.
- **Human-in-the-loop**: no autonomous remediation in Phase 1.
- **OpenTelemetry standard**: developers instrument client services with OpenTelemetry; Phase 1 exports to AWS managed backends.

## Core outcomes

- Faster triage with high-context alerts.
- Lower alert fatigue via suppression and correlation.
- Better MTTR through pre-investigated incidents and linked evidence.
- Auditable incident reasoning and AI usage.

## Example RCA alert message

```
🚨 AIOps Alert: High latency anomaly detected
Service: api-gateway | Env: prod | Account: 123456789012 | Region: eu-central-1
Probable root cause (85% confidence): Deployment v2.3.1 introduced a slower DB query path,
increasing p95 latency from 220ms baseline to 780ms over the last 12 minutes.
Evidence: latency spike started 3 minutes after deployment; DB query duration +240%;
error rate unchanged, indicating performance regression rather than outage.

Recommended steps:
1) Roll back api-gateway to v2.3.0 (or disable feature flag `new-query-planner`).
2) Run EXPLAIN ANALYZE for top 3 slowest queries on `orders` and `payments`.
3) Increase DB read replica capacity temporarily to reduce customer impact.
4) Monitor Grafana dashboard for p95 recovery over the next 15 minutes.
```

## Scope summary

### In scope (Phase 1)

- Multi-account ingestion and normalization
- Hybrid anomaly detection
- Agentic RCA and recommendation workflow
- Slack notifications with Grafana deep-links
- Policy-driven configuration via IaC

### Out of scope (Phase 1)

- Autonomous remediation and change execution
- Multi-cloud support
- Deep APM replacement use cases

## Document map

- [2-product-requirements.md](2-product-requirements.md)
- [3-product-design.md](3-product-design.md)
- [4-technical-architecture.md](4-technical-architecture.md)
- [5-poc.md](5-poc.md)
