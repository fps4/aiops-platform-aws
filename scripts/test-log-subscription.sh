#!/usr/bin/env bash
# Send test events to a CloudWatch log group that is already subscribed to AIOps.
# Defaults to the permanent test group /aws/lambda/aiops-test-sub.
# Usage:
#   scripts/test-log-subscription.sh \
#     [--log-group /aws/lambda/aiops-test-sub] \
#     [--region eu-central-1] [--count 3] [--profile <aws profile>]

set -euo pipefail

LOG_GROUP="/aws/lambda/aiops-test-sub"
REGION="${AWS_REGION:-eu-central-1}"
COUNT=3
PROFILE="${AWS_PROFILE:-}"

usage() {
  cat <<'EOF'
Usage: scripts/test-log-subscription.sh [--log-group <name>] [--region <aws-region>] [--count <n>] [--profile <aws-profile>]

Sends test log events to an existing log group that is already subscribed to the AIOps Firehose.

Defaults:
  log group: /aws/lambda/aiops-test-sub (created by Terraform)
  region   : $AWS_REGION or eu-central-1
  count    : 3
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-group) LOG_GROUP="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --count) COUNT="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

AWS_ARGS=()
[[ -n "$PROFILE" ]] && AWS_ARGS+=(--profile "$PROFILE")
[[ -n "$REGION" ]] && AWS_ARGS+=(--region "$REGION")

echo "Region       : $REGION"
echo "Profile      : ${PROFILE:-default}"
echo "Log group    : $LOG_GROUP"
echo "Test events  : $COUNT"

LOG_STREAM="test-stream-$(date +%s)"
aws logs create-log-stream --log-group-name "$LOG_GROUP" --log-stream-name "$LOG_STREAM" "${AWS_ARGS[@]}"

payload=$(python3 - <<PY
import json, time, os
count=int(os.environ.get('COUNT', '3'))
now=int(time.time() * 1000)
events=[{"timestamp": now + i*10, "message": f"test log {i+1}"} for i in range(count)]
print(json.dumps(events))
PY
)

SEQUENCE=$(aws logs put-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "$LOG_STREAM" \
  --log-events "$payload" \
  --query 'nextSequenceToken' \
  --output text \
  "${AWS_ARGS[@]}")

echo "Sent $COUNT events to $LOG_GROUP/$LOG_STREAM (nextSequenceToken=$SEQUENCE)"
echo "Check Firehose metrics or S3/raw logs for delivery."
