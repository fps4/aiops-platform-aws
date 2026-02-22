#!/usr/bin/env bash
# List CloudWatch log groups and their subscription filters.
# Optional: pass --prefix <log-group-prefix> to limit results (e.g. /aws/lambda/gia-).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/list-log-subscriptions.sh [--prefix <log-group-prefix>] [--region <aws-region>] [--dest-contains <substring>]

Lists CloudWatch log groups and their subscription filters (if any).

Examples:
  scripts/list-log-subscriptions.sh --prefix /aws/lambda/gia-
  scripts/list-log-subscriptions.sh --region eu-central-1
  scripts/list-log-subscriptions.sh --dest-contains aiops
EOF
}

PREFIX=""
REGION="${AWS_REGION:-}"
DEST_SUBSTR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="$2"; shift 2 ;;
    --region)
      REGION="$2"; shift 2 ;;
    --dest-contains)
      DEST_SUBSTR="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage; exit 1 ;;
  esac
done

AWS_ARGS=()
[[ -n "$REGION" ]] && AWS_ARGS+=(--region "$REGION")

# Fetch log groups; if AWS call fails, exit with a helpful message.
if ! log_groups_json=$(aws logs describe-log-groups \
  ${PREFIX:+--log-group-name-prefix "$PREFIX"} \
  --query 'logGroups[].logGroupName' \
  --output json \
  "${AWS_ARGS[@]}" 2>/dev/null); then
  echo "Failed to list CloudWatch log groups (check AWS credentials/region/connectivity)." >&2
  exit 1
fi

log_groups=$(printf '%s' "$log_groups_json" | python3 - <<'PY'
import json,sys
try:
    data=json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)
for name in data or []:
    if name:
        print(name)
PY
)

if [[ -z "$log_groups" ]]; then
  echo "No log groups found${PREFIX:+ with prefix '$PREFIX'}." >&2
  exit 0
fi

printf "%-70s | %-30s | %-80s\n" "Log Group" "Filter Name" "Destination ARN"
printf '%0.s-' {1..190}; echo

subscribed=0
total=0

while IFS= read -r lg; do
  [[ -z "$lg" ]] && continue
  total=$((total + 1))
  filters_json=$(aws logs describe-subscription-filters \
    --log-group-name "$lg" \
    --query 'subscriptionFilters[].{name:filterName,destination:destinationArn}' \
    --output json \
    "${AWS_ARGS[@]}" 2>/dev/null || echo "[]")

  output=$(printf '%s' "$filters_json" | python3 - "$lg" "$DEST_SUBSTR" <<'PY'
import json,sys
lg=sys.argv[1]
substr=sys.argv[2]
filters=json.load(sys.stdin)
lines=[]
for f in filters:
    dest=f.get('destination','-')
    if substr and substr not in dest:
        continue
    lines.append(f"{lg:<70} | {f.get('name','-'):<30} | {dest:<80}")
print("\n".join(lines))
PY
)

  if [[ -n "$output" ]]; then
    subscribed=$((subscribed + 1))
    echo "$output"
  elif [[ -z "$DEST_SUBSTR" ]]; then
    printf "%-70s | %-30s | %s\n" "$lg" "-" "-"
  fi
done <<<"$log_groups"

printf '%0.s-' {1..190}; echo
echo "Subscription filters present on ${subscribed}/${total} log groups""${DEST_SUBSTR:+ (destination contains '$DEST_SUBSTR')}"
