# Platform Team Guide

This guide defines how the platform team operates the AIOps platform as a product for internal engineering teams.

## Primary responsibilities

- Own infrastructure lifecycle (Terraform modules, environments, IAM boundaries).
- Maintain ingestion, normalization, detection, orchestration, and alerting reliability.
- Manage detection policy lifecycle and governance.
- Operate observability stack components (ClickHouse, Grafana, CloudWatch, X-Ray).

## Core workflows

## 1) Environment provisioning and updates

- Apply infra changes via `terraform/environments/<env>` using `-var-file`.
- Run `scripts/get-config.sh <env>` after deployment updates.
- Run post-apply provisioning:
  - `scripts/provision-clickhouse.sh`
  - `scripts/provision-grafana.sh`

## 2) Ingestion onboarding and validation

- Review log subscription requests from product engineering teams.
- Ensure subscription filters include needed signal (`ERROR`, `WARN`, key latency fields).
- Validate end-to-end flow:
  - Firehose `IncomingRecords`
  - S3 raw object delivery
  - ClickHouse writes

## 3) Policy lifecycle management

- Author policies in YAML (`policies/default-policies.yaml`).
- Validate with `python scripts/validate-policy.py ...`.
- Load with `scripts/load-policies.sh --file ...`.
- Track policy changes with changelog notes in PR descriptions.

## 4) Incident support and escalation

- Validate anomaly confidence and correlated evidence.
- Confirm RCA recommendations are technically safe before broad communication.
- Escalate to service owners when mitigation needs application-level change.

## Handoffs

- To Product Engineering: ownership of service-level fixes and OTEL instrumentation quality.
- To SRE On-Call: incident command, severity handling, stakeholder communication.
- To Security/Compliance: suspicious signals, access anomalies, and audit requirements.
