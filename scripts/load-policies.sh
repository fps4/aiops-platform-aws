#!/usr/bin/env bash
# Load detection policies from a YAML file into the DynamoDB policy_store table.
#
# Usage:
#   scripts/load-policies.sh [--file <path>] [--env <env>] [--region <region>]
#
# Defaults:
#   --file    policies/examples/default-policies.yaml
#   --env     dev
#   --region  eu-central-1

set -euo pipefail

FILE="policies/examples/default-policies.yaml"
ENV="dev"
REGION="${AWS_REGION:-eu-central-1}"
PROJECT_PREFIX="${PROJECT_PREFIX:-aiops}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)    FILE="$2";           shift 2 ;;
    --env)     ENV="$2";            shift 2 ;;
    --region)  REGION="$2";         shift 2 ;;
    --prefix)  PROJECT_PREFIX="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

TABLE="${PROJECT_PREFIX}-${ENV}-policy-store"

# Use project venv if present
PYTHON="python3"
if [ -f "venv/bin/python3" ]; then PYTHON="venv/bin/python3"; fi

echo "→ Loading policies from '${FILE}' into DynamoDB table '${TABLE}' (${REGION})..."

"${PYTHON}" - <<PYTHON
import sys
import yaml
import boto3
from decimal import Decimal

with open("${FILE}") as f:
    data = yaml.safe_load(f)

dynamodb = boto3.resource("dynamodb", region_name="${REGION}")
table = dynamodb.Table("${TABLE}")

policies = data.get("detection_policies", [])
if not policies:
    print("No detection_policies found in file — nothing loaded.")
    sys.exit(0)

for p in policies:
    det     = p.get("detection", {})
    actions = p.get("actions", {})
    scope   = p.get("scope", {})

    services = scope.get("services", [])

    item = {
        "policy_id":               p["name"],
        "enabled":                 True,
        "name":                    p["name"],
        "description":             p.get("description", ""),
        "service":                 services[0] if services else "unknown",
        "services":                services,
        "accounts":                scope.get("accounts", []),
        "detection_type":          det.get("type", "statistical"),
        "sensitivity":             det.get("sensitivity", "medium"),
        "metrics":                 [det["metric"]] if "metric" in det else [],
        "baseline_window":         det.get("baseline_window", "7d"),
        "alert":                   actions.get("alert", True),
        "run_rca":                 actions.get("run_rca", False),
        "agent_provider":          actions.get("agent_provider", "bedrock"),
        "suppress_similar_minutes": actions.get("suppress_similar_minutes", 30),
    }

    # Flatten threshold sub-keys, converting floats to Decimal for DynamoDB
    for k, v in det.get("threshold", {}).items():
        item[k] = Decimal(str(v)) if isinstance(v, float) else v

    table.put_item(Item=item)
    print(f"  ✓ {item['policy_id']}  [{item['detection_type']} / {item['sensitivity']}]  services={item['services']}")

print(f"\n✓ Loaded {len(policies)} policies into {table.name}")
PYTHON
