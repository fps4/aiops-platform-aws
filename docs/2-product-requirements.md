# Product Requirements

## Problem statement

Platform and SRE teams in multi-account AWS environments lose time to noisy alerts and manual cross-system correlation. The product must detect meaningful anomalies and provide investigation-ready context before humans engage.

## Primary users

### Platform/SRE teams

Responsibilities:
- Define and tune detection policies
- Operate platform infrastructure and guardrails
- Respond to proactive anomaly alerts
- Validate RCA quality and improve policies over time

Goals:
- Reduce MTTR
- Improve signal-to-noise ratio
- Maintain centralized visibility across accounts and services

### Product Engineering teams

Responsibilities:
- Instrument owned services with OpenTelemetry and propagate trace context
- Receive and triage service-specific anomaly/RCA alerts with SRE partners
- Validate probable root causes against recent code/config changes
- Execute or coordinate service-level remediation and rollback decisions

Goals:
- Detect regressions earlier in the service lifecycle
- Reduce time to confirm or reject RCA hypotheses
- Improve release confidence through better production feedback loops

## Functional requirements

### FR-1 Multi-account ingestion

- Ingest logs and events from multiple AWS accounts.
- Normalize incoming signals to a canonical schema including account, region, service, environment, and deployment metadata.
- Preserve raw records for replay and audit.

### FR-2 Hybrid anomaly detection

- Support statistical detection (STL, changepoint, z-score/EWMA patterns).
- Support rule-based guardrails (error rate, latency, traffic, security patterns).
- Produce structured anomaly objects with baseline, deviation, severity, confidence, and related evidence.

### FR-3 Agentic investigation workflow

- Trigger a deterministic, replayable pipeline:
  - Detection
  - Correlation
  - Historical comparison
  - RCA synthesis
  - Recommendation generation
- Keep evidence chain and confidence scoring per stage.

### FR-4 Alerting and investigation handoff

- Deliver proactive Slack alerts to a shared channel.
- Include what happened, likely cause, confidence, and suggested next steps.
- Include deep-links to pre-filtered Grafana dashboards.

### FR-5 Policy-driven operations

- Configure detection, suppression, escalation, and model/provider selection through version-controlled policy files and IaC workflows.
- Support service/account scoping and cooldown windows.

### FR-6 AI provider abstraction

- Allow per-agent model/provider selection through a unified interface.
- Support commercial and self-hosted models.
- Capture prompt/response audit data and estimated usage/cost metadata.

### FR-7 Telemetry instrumentation standard

- Application/client services must use OpenTelemetry instrumentation for traces and metrics.
- Propagate trace context across service boundaries and include operational identifiers (`anomaly_id`, `workflow_id`, `service`, `environment` where applicable).
- Phase 1 telemetry exports target AWS managed backends (X-Ray for tracing, CloudWatch for metrics), with optional AMP for Prometheus-style metrics.

## Non-functional requirements

### Performance

- Alert latency from detection to Slack should remain near real-time for operational response (target P95 under a few minutes).
- Dashboard deep-links must load quickly with pre-applied filters.

### Reliability

- Retry transient failures in ingestion and agent workflow stages.
- Prevent data loss in ingestion path with durable sinks.
- Provide dead-letter or failure visibility for notification failures.

### Security and privacy

- Enforce least-privilege cross-account access.
- Redact sensitive fields before external AI calls when required.
- Maintain auditable decision trails.

### Scalability

- Scale across dozens of AWS accounts in MVP and higher in later phases.
- Handle concurrent anomalies without workflow collapse or noisy duplication.

### Cost control

- Apply per-agent/provider budget limits.
- Default retention and lifecycle controls for observability data.
- Favor serverless or right-sized infrastructure patterns.

## Success metrics

- MTTR reduction relative to current baseline.
- False positive reduction and alert quality improvement.
- RCA usefulness/accuracy based on operator feedback.
- Adoption by on-call engineers, platform operators, and product engineering service owners.

## Explicit non-goals

- Autonomous remediation in current phase
- Multi-cloud parity in current phase
- Replacing full APM suites
