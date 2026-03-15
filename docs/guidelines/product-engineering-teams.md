# Product Engineering Teams Guide

This guide helps service teams onboard to the AIOps Agentic System and own alert outcomes for their systems.

## What your team owns

- Service telemetry quality (logs, metrics, traces).
- OTEL instrumentation in application code and runtime.
- Service-specific detection policy inputs and tuning feedback.
- Mitigation and remediation actions from RCA alerts.

## Onboarding checklist

- Add CloudWatch log subscription for each production service log group.
- Emit structured logs with service name, severity, and timestamps.
- Implement OTEL instrumentation and context propagation across service boundaries.
- Validate traces and metrics appear in agreed backends.
- Confirm your team can receive and respond to Slack alerts.

## OTEL expectations

- Instrument code with OpenTelemetry SDKs and semantic conventions.
- Attach resource attributes (`service.name`, `service.version`, `deployment.environment`).
- Propagate trace context across HTTP/event boundaries.
- Runtime collection model:
  - Lambda: ADOT layer/extension pattern.
  - ECS/EKS/VM: sidecar, daemon, or gateway collector pattern.

## Operating model after onboarding

- Treat RCA alerts as triage-ready hypotheses, not final truth.
- Validate recommendation steps before production execution.
- Provide feedback to platform team when false positives/negatives occur.
- Update runbooks when recurring patterns are discovered.

## Escalation boundaries

- Platform issue: ingestion gaps, policy loading failures, alert pipeline failures.
- Service issue: regressions, rollout defects, dependency failures, saturation.
