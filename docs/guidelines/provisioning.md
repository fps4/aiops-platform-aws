# Provisioning Guide

After `terraform apply` creates the EC2 instances, two provisioning scripts finish the setup. Both run entirely via **SSM** — no SSH access needed.

## Overview

| Step | Script | What it does |
|------|--------|--------------|
| 1 | `scripts/provision-clickhouse.sh` | Applies `scripts/init-clickhouse-schema.sql` on the ClickHouse instance |
| 2 | `scripts/provision-grafana.sh` | Writes datasource config, dashboard provider, loads dashboard JSON files |

Both scripts pull instance IDs from Terraform outputs, so run them from the repo root after a successful `terraform apply`.

---

## Prerequisites

```bash
# AWS CLI v2 + SSM plugin (see docs/guidelines/ssm-access.md)
aws --version
session-manager-plugin --version

# Python 3 + boto3 (use project venv)
source venv/bin/activate
pip install boto3

# Terraform state must be accessible
cd terraform/environments/dev && terraform output clickhouse_instance_id
```

---

## Step 1: ClickHouse Schema

```bash
scripts/provision-clickhouse.sh
# or with explicit env/region:
scripts/provision-clickhouse.sh --env dev --region eu-central-1
```

This base64-encodes `scripts/init-clickhouse-schema.sql` and sends it to the ClickHouse instance via `aws ssm send-command`. On the instance it runs:

```bash
clickhouse-client --multiquery < /tmp/aiops-schema.sql
```

Creates tables `aiops.logs` and `aiops.anomalies` (idempotent — uses `CREATE TABLE IF NOT EXISTS`).

**Expected output:**

```
→ Provisioning ClickHouse schema (env=dev, region=eu-central-1)
  Fetching instance ID from Terraform...
  Instance: i-0abc123def456789a
  Checking SSM connectivity...
  Schema: scripts/init-clickhouse-schema.sql (1487 bytes)
  Sending schema to instance...
    Command ID: abc12345-...
    ... InProgress
    ✓ Schema applied
      --- Tables in aiops ---
      anomalies
      logs

✓ ClickHouse schema provisioned
```

---

## Step 2: Grafana

```bash
scripts/provision-grafana.sh
# with non-default password:
scripts/provision-grafana.sh --grafana-password mysecretpassword
```

**Phase 1** — writes two provisioning files on the Grafana instance and restarts the service:

| File on instance | Source |
|------------------|--------|
| `/etc/grafana/provisioning/datasources/clickhouse.yaml` | `config/grafana/provisioning/datasources/clickhouse.yaml.tpl` with `__CLICKHOUSE_HOST__` replaced by ClickHouse private IP |
| `/etc/grafana/provisioning/dashboards/aiops.yaml` | `config/grafana/provisioning/dashboards/provider.yaml` |

**Phase 2** — loads any `config/grafana/dashboards/*.json` files into Grafana via its HTTP API (`/api/dashboards/import`). If there are no JSON files, this step is skipped.

**Default Grafana credentials**: RPM installs default to `admin` / `admin`. The `--grafana-password` flag is used for the API calls in Phase 2. Change the admin password on first login (Grafana will prompt for this in the UI).

---

## Adding Dashboards

Dashboards are version-controlled in `config/grafana/dashboards/`. To add one:

1. Build the dashboard in the Grafana UI
2. Export: **Dashboard → Share → Export → Save to file**
3. Save the JSON file to `config/grafana/dashboards/<name>.json`
4. Run `scripts/provision-grafana.sh` — it will import/overwrite all JSON files

The provisioning script uses `"overwrite": true` so re-running is safe. Dashboards are stored in Grafana's internal database, so they persist across Grafana restarts.

---

## Config Files in Repository

```
config/
  grafana/
    provisioning/
      datasources/
        clickhouse.yaml.tpl     # ClickHouse datasource template
      dashboards/
        provider.yaml           # tells Grafana to watch /var/lib/grafana/dashboards/
    dashboards/
      *.json                    # dashboard JSON files (commit here)
```

The `*.tpl` file uses a single placeholder: `__CLICKHOUSE_HOST__`. The provisioning script substitutes the actual ClickHouse private IP at runtime (`sed`), then base64-encodes the result before sending via SSM.

---

## Troubleshooting

**`SSM agent not online`**
The instance is still running its `user_data` bootstrap (installs ClickHouse/Grafana via dnf, waits for EBS). Wait 3–5 minutes after `terraform apply` and retry.

**`clickhouse_instance_id is empty`**
The ClickHouse instance wasn't deployed. Check that `subnet_id` is set in `terraform/environments/dev/resources.tf` and re-run `terraform apply`.

**ClickHouse `--multiquery` fails**
If the instance hasn't finished the `user_data` bootstrap (EBS not yet mounted, service not yet started), the schema command will fail. SSM will report the error. Re-run the script after a few minutes.

**Grafana API returns 401**
The password passed to `--grafana-password` doesn't match the current admin password. If the password was changed in the UI, pass the updated password:
```bash
scripts/provision-grafana.sh --grafana-password <current-password>
```

**Dashboard import fails with 400**
The JSON file is not a valid Grafana dashboard export (missing required fields). Export it fresh from the UI using **Share → Export → Save to file**.
