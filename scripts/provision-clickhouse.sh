#!/usr/bin/env bash
# Apply the AIOps ClickHouse schema on the ClickHouse EC2 instance via SSM.
#
# Usage:
#   scripts/provision-clickhouse.sh [--env <env>] [--region <region>]
#
# Defaults:
#   --env     dev
#   --region  eu-central-1
#
# Prerequisites:
#   - AWS CLI v2 with Session Manager plugin installed
#   - Terraform state initialized in terraform/environments/<env>/
#   - IAM: ssm:SendCommand on the ClickHouse instance
#   - Python 3 with boto3 (project venv or system)

set -euo pipefail

ENVIRONMENT="dev"
REGION="${AWS_REGION:-eu-central-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCHEMA_FILE="${REPO_ROOT}/scripts/init-clickhouse-schema.sql"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)    ENVIRONMENT="$2"; shift 2 ;;
    --region) REGION="$2";      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo "→ Provisioning ClickHouse schema (env=${ENVIRONMENT}, region=${REGION})"

# Use project venv if available (same convention as load-policies.sh)
PYTHON="python3"
if [ -f "${REPO_ROOT}/venv/bin/python3" ]; then PYTHON="${REPO_ROOT}/venv/bin/python3"; fi

# --- Resolve instance ID from Terraform output ---
TF_DIR="${REPO_ROOT}/terraform/environments/${ENVIRONMENT}"
[ -d "${TF_DIR}" ] || { echo "ERROR: Terraform dir not found: ${TF_DIR}" >&2; exit 1; }

echo "  Fetching instance ID from Terraform..."
INSTANCE_ID=$(cd "${TF_DIR}" && terraform output -raw clickhouse_instance_id 2>/dev/null)
[ -n "${INSTANCE_ID}" ] || {
  echo "ERROR: clickhouse_instance_id is empty. Is the ClickHouse instance deployed?" >&2; exit 1
}
echo "  Instance: ${INSTANCE_ID}"

# --- Check SSM connectivity ---
echo "  Checking SSM connectivity..."
PING=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text --region "${REGION}" 2>/dev/null || echo "None")
[ "${PING}" = "Online" ] || {
  echo "ERROR: SSM agent not online (status: ${PING})."
  echo "  The instance may still be finishing its user_data bootstrap (can take 3-5 min)."
  echo "  Check: aws ssm describe-instance-information --region ${REGION}"
  exit 1
}

# --- Base64-encode schema SQL ---
[ -f "${SCHEMA_FILE}" ] || { echo "ERROR: Schema file not found: ${SCHEMA_FILE}" >&2; exit 1; }
SCHEMA_B64=$(base64 < "${SCHEMA_FILE}" | tr -d '\n')
echo "  Schema: ${SCHEMA_FILE} ($(wc -c < "${SCHEMA_FILE}" | tr -d ' ') bytes)"

# --- Send schema and run via SSM ---
echo "  Sending schema to instance..."

"${PYTHON}" - <<PYTHON
import sys, time, boto3

ssm = boto3.client("ssm", region_name="${REGION}")

commands = [
    "set -e",
    "echo '${SCHEMA_B64}' | base64 -d > /tmp/aiops-schema.sql",
    # SSM agent starts before user_data finishes — wait up to 5 min for clickhouse-client
    "echo '  Waiting for clickhouse-client to be available...'",
    "for i in \$(seq 1 30); do command -v clickhouse-client > /dev/null 2>&1 && break || sleep 10; done",
    "command -v clickhouse-client > /dev/null 2>&1 || { echo 'ERROR: clickhouse-client not found after 5 min'; exit 1; }",
    "clickhouse-client --multiquery < /tmp/aiops-schema.sql",
    "rm -f /tmp/aiops-schema.sql",
    "echo '--- Tables in aiops ---'",
    "clickhouse-client -q 'SHOW TABLES FROM aiops FORMAT TabSeparated'",
]

resp = ssm.send_command(
    InstanceIds=["${INSTANCE_ID}"],
    DocumentName="AWS-RunShellScript",
    Parameters={"commands": commands},
    TimeoutSeconds=360,
    Comment="AIOps ClickHouse schema provision",
)
command_id = resp["Command"]["CommandId"]
print(f"  Command ID: {command_id}")

time.sleep(3)  # SSM propagation delay

for _ in range(40):
    try:
        inv = ssm.get_command_invocation(CommandId=command_id, InstanceId="${INSTANCE_ID}")
    except ssm.exceptions.InvocationDoesNotExist:
        time.sleep(3)
        continue
    status = inv["Status"]
    if status == "Success":
        print("  ✓ Schema applied")
        stdout = inv["StandardOutputContent"].strip()
        if stdout:
            for line in stdout.splitlines():
                print(f"    {line}")
        sys.exit(0)
    elif status in ("Failed", "TimedOut", "Cancelled", "DeliveryTimedOut"):
        print(f"  ✗ Command {status}", file=sys.stderr)
        stderr = inv.get("StandardErrorContent", "").strip()
        if stderr:
            print(stderr, file=sys.stderr)
        sys.exit(1)
    print(f"  ... {status}")
    time.sleep(5)

print("ERROR: Timed out waiting for SSM command", file=sys.stderr)
sys.exit(1)
PYTHON

echo ""
echo "✓ ClickHouse schema provisioned"
echo "  To verify: see docs/guidelines/ssm-access.md for ClickHouse port-forwarding instructions"
