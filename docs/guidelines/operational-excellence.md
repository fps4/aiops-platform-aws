# Operational Excellence Guide

This activity guide defines day-2 operations for platform reliability, cost, security, and incident readiness.

## Monitoring and alerting baseline

- Pipeline health alarms for Lambda, Fargate detector, and orchestrator failures
- Data freshness alarm for ClickHouse ingest lag
- Cost alarms for AI spend and core infrastructure
- RCA quality tracking (confidence vs validated outcome)

## Telemetry operations baseline

- OpenTelemetry instrumentation in platform and client services
- Trace backend: AWS X-Ray (Phase 1 baseline)
- Metrics backend: CloudWatch (optional AMP where PromQL is needed)
- Correlation IDs propagated across components (`anomaly_id`, `workflow_id`, `service`)

## Reliability and recovery

- ClickHouse auto-restart via systemd with persistent EBS volume
- S3 lifecycle policies for raw and audit logs
- Terraform state versioning for control-plane recovery
- Optional phase-2 cross-region replication for raw archives

## Security and compliance checks

- IAM role-only access; no long-lived credentials
- SSM-only instance access (no SSH/bastion)
- Encryption at rest and TLS in transit
- Prompt/response audit records retained in S3

## Cost optimization practices

- Keep serverless components event-driven and right-sized
- Tune detector cadence and policy sensitivity to reduce noise and spend
- Use storage lifecycle tiers and retention windows intentionally
- Enforce per-agent cost caps in policy configuration

## Incident readiness

- Follow [sre-oncall.md](./sre-oncall.md) for triage cadence and communication
- Validate recommendations before production execution
- Feed false-positive and false-negative findings back to platform policy owners
