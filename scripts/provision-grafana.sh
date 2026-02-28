#!/usr/bin/env bash
# Configure Grafana on the Grafana EC2 instance via SSM:
#   - Writes ClickHouse datasource (config/grafana/provisioning/datasources/clickhouse.yaml.tpl)
#   - Writes dashboard filesystem provider (config/grafana/provisioning/dashboards/provider.yaml)
#   - Loads any dashboard JSON files from config/grafana/dashboards/*.json via Grafana HTTP API
#
# Usage:
#   scripts/provision-grafana.sh [--env <env>] [--region <region>] [--grafana-password <pwd>]
#
# Defaults:
#   --env              dev
#   --region           eu-central-1
#   --grafana-password admin   (RPM install default; change after first login)
#
# Prerequisites:
#   - AWS CLI v2 with Session Manager plugin installed
#   - Terraform state initialized in terraform/environments/<env>/
#   - IAM: ssm:SendCommand + ec2:DescribeInstances
#   - Python 3 with boto3 (project venv or system)

set -euo pipefail

ENVIRONMENT="dev"
REGION="${AWS_REGION:-eu-central-1}"
GRAFANA_PASSWORD="admin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATASOURCE_TPL="${REPO_ROOT}/config/grafana/provisioning/datasources/clickhouse.yaml.tpl"
DASHBOARD_PROVIDER="${REPO_ROOT}/config/grafana/provisioning/dashboards/provider.yaml"
DASHBOARD_DIR="${REPO_ROOT}/config/grafana/dashboards"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)              ENVIRONMENT="$2";      shift 2 ;;
    --region)           REGION="$2";           shift 2 ;;
    --grafana-password) GRAFANA_PASSWORD="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo "→ Provisioning Grafana (env=${ENVIRONMENT}, region=${REGION})"

PYTHON="python3"
if [ -f "${REPO_ROOT}/venv/bin/python3" ]; then PYTHON="${REPO_ROOT}/venv/bin/python3"; fi

# --- Resolve instance IDs and ClickHouse private IP from Terraform + EC2 ---
TF_DIR="${REPO_ROOT}/terraform/environments/${ENVIRONMENT}"
[ -d "${TF_DIR}" ] || { echo "ERROR: Terraform dir not found: ${TF_DIR}" >&2; exit 1; }

echo "  Fetching outputs from Terraform..."
GRAFANA_INSTANCE_ID=$(cd "${TF_DIR}" && terraform output -raw grafana_instance_id 2>/dev/null)
CLICKHOUSE_INSTANCE_ID=$(cd "${TF_DIR}" && terraform output -raw clickhouse_instance_id 2>/dev/null)

[ -n "${GRAFANA_INSTANCE_ID}" ] || {
  echo "ERROR: grafana_instance_id is empty. Is the Grafana instance deployed?" >&2; exit 1
}
[ -n "${CLICKHOUSE_INSTANCE_ID}" ] || {
  echo "ERROR: clickhouse_instance_id is empty. Is the ClickHouse instance deployed?" >&2; exit 1
}

echo "  Grafana instance:    ${GRAFANA_INSTANCE_ID}"
echo "  ClickHouse instance: ${CLICKHOUSE_INSTANCE_ID}"

# Resolve ClickHouse private IP from EC2 (not a Terraform output at environment level)
CLICKHOUSE_HOST=$(aws ec2 describe-instances \
  --instance-ids "${CLICKHOUSE_INSTANCE_ID}" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text --region "${REGION}" 2>/dev/null)
[ -n "${CLICKHOUSE_HOST}" ] && [ "${CLICKHOUSE_HOST}" != "None" ] || {
  echo "ERROR: Could not resolve ClickHouse private IP for ${CLICKHOUSE_INSTANCE_ID}" >&2; exit 1
}
echo "  ClickHouse host:     ${CLICKHOUSE_HOST}"

# --- Check SSM connectivity on Grafana instance ---
echo "  Checking SSM connectivity..."
PING=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${GRAFANA_INSTANCE_ID}" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text --region "${REGION}" 2>/dev/null || echo "None")
[ "${PING}" = "Online" ] || {
  echo "ERROR: Grafana SSM agent not online (status: ${PING})."
  echo "  The instance may still be finishing its user_data bootstrap."
  exit 1
}

# --- Build config file content (substitute host, base64-encode) ---
[ -f "${DATASOURCE_TPL}" ] || { echo "ERROR: Not found: ${DATASOURCE_TPL}" >&2; exit 1; }
[ -f "${DASHBOARD_PROVIDER}" ] || { echo "ERROR: Not found: ${DASHBOARD_PROVIDER}" >&2; exit 1; }

DATASOURCE_B64=$(sed "s/__CLICKHOUSE_HOST__/${CLICKHOUSE_HOST}/g" "${DATASOURCE_TPL}" | base64 | tr -d '\n')
PROVIDER_B64=$(base64 < "${DASHBOARD_PROVIDER}" | tr -d '\n')

# ─── Phase 1: Write provisioning config and restart Grafana ───────────────────

echo ""
echo "  Phase 1: Writing datasource + dashboard provider config..."

"${PYTHON}" - <<PYTHON
import sys, time, boto3

ssm = boto3.client("ssm", region_name="${REGION}")

commands = [
    "set -e",
    # Datasource YAML
    "mkdir -p /etc/grafana/provisioning/datasources",
    "echo '${DATASOURCE_B64}' | base64 -d > /etc/grafana/provisioning/datasources/clickhouse.yaml",
    # Dashboard provider YAML
    "mkdir -p /etc/grafana/provisioning/dashboards",
    "echo '${PROVIDER_B64}' | base64 -d > /etc/grafana/provisioning/dashboards/aiops.yaml",
    # Dashboard storage directory (Grafana must own it)
    "mkdir -p /var/lib/grafana/dashboards",
    "chown grafana:grafana /var/lib/grafana/dashboards",
    # Restart to pick up provisioning files
    "systemctl restart grafana-server",
    # Wait for HTTP to be ready (up to 60s)
    "for i in \$(seq 1 20); do curl -sf http://localhost:3000/api/health > /dev/null && break || sleep 3; done",
    "curl -sf http://localhost:3000/api/health",
    "echo '  Grafana is up'",
]

resp = ssm.send_command(
    InstanceIds=["${GRAFANA_INSTANCE_ID}"],
    DocumentName="AWS-RunShellScript",
    Parameters={"commands": commands},
    TimeoutSeconds=120,
    Comment="AIOps Grafana config provision",
)
command_id = resp["Command"]["CommandId"]
print(f"    Command ID: {command_id}")

time.sleep(3)

for _ in range(40):
    try:
        inv = ssm.get_command_invocation(CommandId=command_id, InstanceId="${GRAFANA_INSTANCE_ID}")
    except ssm.exceptions.InvocationDoesNotExist:
        time.sleep(3)
        continue
    status = inv["Status"]
    if status == "Success":
        print("    ✓ Config written and Grafana restarted")
        sys.exit(0)
    elif status in ("Failed", "TimedOut", "Cancelled", "DeliveryTimedOut"):
        print(f"    ✗ {status}", file=sys.stderr)
        stderr = inv.get("StandardErrorContent", "").strip()
        if stderr:
            print(stderr, file=sys.stderr)
        sys.exit(1)
    print(f"    ... {status}")
    time.sleep(5)

print("ERROR: Timed out waiting for SSM command", file=sys.stderr)
sys.exit(1)
PYTHON

# ─── Phase 2: Load dashboard JSON files via Grafana HTTP API ─────────────────

echo ""
echo "  Phase 2: Loading dashboard JSON files..."

shopt -s nullglob
json_files=("${DASHBOARD_DIR}"/*.json)

if [ ${#json_files[@]} -eq 0 ]; then
  echo "  No *.json files in ${DASHBOARD_DIR} — skipping."
  echo "  Add dashboard JSON files there and re-run this script to load them."
else
  for dashboard_file in "${json_files[@]}"; do
    dashboard_name="$(basename "${dashboard_file}" .json)"
    echo "  Loading: ${dashboard_name}..."

    DASH_B64=$(base64 < "${dashboard_file}" | tr -d '\n')

    "${PYTHON}" - <<PYTHON
import sys, time, boto3

ssm = boto3.client("ssm", region_name="${REGION}")

commands = [
    "set -e",
    # Decode dashboard JSON to disk
    "echo '${DASH_B64}' | base64 -d > /tmp/dash-raw.json",
    # Wrap in Grafana import envelope (remove 'id' so Grafana assigns a new one)
    "python3 -c '"
    "import json; "
    "d=json.load(open(\"/tmp/dash-raw.json\")); "
    "d.pop(\"id\", None); "
    "json.dump({\"dashboard\": d, \"overwrite\": True, \"folderId\": 0}, open(\"/tmp/dash-import.json\", \"w\"))"
    "'",
    # POST to Grafana import API
    "curl -sf -u 'admin:${GRAFANA_PASSWORD}' "
    "-X POST http://localhost:3000/api/dashboards/import "
    "-H 'Content-Type: application/json' "
    "-d @/tmp/dash-import.json",
    "rm -f /tmp/dash-raw.json /tmp/dash-import.json",
]

resp = ssm.send_command(
    InstanceIds=["${GRAFANA_INSTANCE_ID}"],
    DocumentName="AWS-RunShellScript",
    Parameters={"commands": commands},
    TimeoutSeconds=60,
    Comment="AIOps Grafana dashboard: ${dashboard_name}",
)
command_id = resp["Command"]["CommandId"]

time.sleep(3)

for _ in range(20):
    try:
        inv = ssm.get_command_invocation(CommandId=command_id, InstanceId="${GRAFANA_INSTANCE_ID}")
    except ssm.exceptions.InvocationDoesNotExist:
        time.sleep(3)
        continue
    status = inv["Status"]
    if status == "Success":
        print("    ✓ ${dashboard_name}")
        stdout = inv["StandardOutputContent"].strip()
        if stdout:
            for line in stdout.splitlines():
                if line.strip():
                    print(f"      {line}")
        sys.exit(0)
    elif status in ("Failed", "TimedOut", "Cancelled", "DeliveryTimedOut"):
        print(f"    ✗ ${dashboard_name}: {status}", file=sys.stderr)
        stderr = inv.get("StandardErrorContent", "").strip()
        if stderr:
            print(stderr, file=sys.stderr)
        sys.exit(1)
    print(f"    ... {status}")
    time.sleep(5)

print("ERROR: Timed out loading ${dashboard_name}", file=sys.stderr)
sys.exit(1)
PYTHON

  done
fi

echo ""
echo "✓ Grafana provisioned"
echo "  Access via SSM port-forward: see docs/guidelines/ssm-access.md"
