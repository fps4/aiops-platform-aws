# SRE On-Call Guide

This guide defines how on-call responders consume AIOps alerts and drive incidents to resolution.

## Incident response objectives

- Reduce mean time to acknowledge and isolate root cause.
- Keep communication clear and evidence-based.
- Avoid risky remediation without validation.

## Triage sequence

1. Acknowledge alert in Slack and assign incident owner.
2. Verify impacted service, environment, and blast radius.
3. Review RCA summary, confidence, correlated events, and recommendations.
4. Open Grafana/ClickHouse context links and validate signal quality.
5. Decide action:
   - immediate rollback
   - traffic shaping/degradation
   - dependency failover
   - no-op with monitoring if signal is false positive

## Decision guardrails

- Do not execute destructive remediation without service-owner confirmation.
- Prefer reversible actions first.
- If confidence is low, collect additional evidence before major interventions.

## Communication pattern

- Share one concise status update per decision point:
  - current impact
  - most likely cause
  - current mitigation
  - next check time/event

## Post-incident follow-up

- Confirm closure criteria are met (error rate, latency, saturation normalize).
- Log false-positive/false-negative feedback to platform team.
- Add or update runbook steps for repeated failure modes.
