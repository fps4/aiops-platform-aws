# POC Plan

## Objective

Demonstrate that the platform can detect anomalies, perform automated pre-investigation, and deliver high-quality RCA alerts that reduce operator investigation time.

## POC scope

Included:
- Multi-account signal ingestion into centralized observability account
- Hybrid anomaly detection (statistical + rule-based)
- Orchestrated RCA pipeline ending in Slack alert
- Grafana deep-link to evidence dashboards
- IaC-based policy management

Excluded:
- Autonomous remediation
- Multi-cloud ingestion
- Advanced interactive Slack actions

## POC success criteria

- Logs/events from test accounts are ingested and queryable.
- At least one synthetic incident is detected automatically.
- RCA summary includes confidence and evidence links.
- Slack alert is delivered with working Grafana deep-link.
- Operators can validate conclusion quickly via dashboard context.

## Test scenarios

### Scenario A: Deployment-induced latency spike

- Inject elevated latency after controlled deployment.
- Expect correlation with deployment metadata and service impact.

### Scenario B: Error rate regression

- Introduce controlled application errors.
- Expect rule-based detection and RCA hypothesis around recent changes.

### Scenario C: Infrastructure degradation signal

- Simulate resource pressure (e.g., throttling).
- Expect correlation to infra metrics/events and runbook recommendation.

## POC execution phases

### Phase P1: Baseline platform bring-up

- Provision infrastructure with Terraform
- Confirm ingestion and storage paths
- Initialize dashboards and policies

### Phase P2: Detection and orchestration validation

- Enable detectors and stream trigger
- Validate full agent pipeline and audit records
- Tune suppression and confidence thresholds

### Phase P3: Operational validation

- Run synthetic incidents repeatedly
- Measure alert quality and response usability
- Capture cost/performance observations

## Evidence to collect

- Sample anomaly records
- Agent output snapshots by stage
- Slack alert examples
- Dashboard screenshots or query outputs
- Latency and reliability metrics for the end-to-end flow

## Exit criteria

The POC is successful when stakeholders can see a repeatable path from signal ingestion to high-context incident alerting with enough evidence to drive faster, more confident incident response.

