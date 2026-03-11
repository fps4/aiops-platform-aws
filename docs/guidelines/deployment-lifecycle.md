# Deployment Lifecycle Guide

This activity guide defines how to deploy and evolve the platform safely across environments.

## Scope

- Central account setup and updates
- Member account onboarding
- Policy loading and rollout validation
- Access verification for Grafana and ClickHouse

## Prerequisites

- Terraform initialized in `terraform/environments/<env>`
- Valid `<env>.tfvars` and AWS credentials
- SSM Session Manager access for target instances

## Deployment sequence

1. Apply infrastructure with environment var-file:
   ```bash
   cd terraform/environments/dev
   terraform init
   terraform plan -var-file=dev.tfvars
   terraform apply -var-file=dev.tfvars
   ```
2. Refresh deployed configuration:
   ```bash
   ./scripts/get-config.sh dev
   ```
3. Provision ClickHouse schema:
   ```bash
   ./scripts/provision-clickhouse.sh --env dev --region eu-central-1
   ```
4. Provision Grafana datasource and dashboards:
   ```bash
   ./scripts/provision-grafana.sh
   ```
5. Load or update detection policies:
   ```bash
   scripts/load-policies.sh --file policies/default-policies.yaml
   ```

## Member account onboarding

Use [subscribing-to-the-platform.md](./subscribing-to-the-platform.md) for same-account and cross-account log subscription patterns.

## Post-deploy verification

- Firehose receives records (`IncomingRecords`)
- S3 receives raw objects
- ClickHouse has fresh records in `aiops.logs`
- Grafana datasource is healthy and dashboards load
- Anomaly-to-alert path works with synthetic test data

## Rollback guidance

- Prefer Terraform-based rollback for infrastructure regressions.
- For policy regressions, revert YAML policy version and reload.
- For service access regressions, verify SSM connectivity before deeper rollback.
