#!/usr/bin/env bash
# Import OpenSearch index template and dashboard saved objects.
#
# Usage:
#   ./scripts/import-opensearch-dashboards.sh [dev|staging|prod]
#
# Prerequisites:
#   - AWS CLI configured with valid credentials
#   - awscurl installed: pip install awscurl
#   - jq installed for JSON pretty-printing (optional)
#
# The script:
#   1. Resolves the OpenSearch endpoint from SSM or the OPENSEARCH_ENDPOINT env var
#   2. Creates the anomalies-* index template so field types are set correctly
#   3. Imports dashboards/all-dashboards.ndjson via the Dashboards saved-objects API

set -euo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-eu-central-1}"
SSM_PREFIX="/aiops-platform/${ENVIRONMENT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NDJSON_FILE="${SCRIPT_DIR}/../dashboards/all-dashboards.ndjson"

# ── Resolve OpenSearch endpoint ───────────────────────────────────────────────

if [[ -z "${OPENSEARCH_ENDPOINT:-}" ]]; then
  echo "[INFO] Fetching OPENSEARCH_ENDPOINT from SSM: ${SSM_PREFIX}/opensearch_endpoint"
  OPENSEARCH_ENDPOINT=$(aws ssm get-parameter \
    --name "${SSM_PREFIX}/opensearch_endpoint" \
    --region "${REGION}" \
    --query "Parameter.Value" \
    --output text 2>/dev/null || true)
fi

if [[ -z "${OPENSEARCH_ENDPOINT:-}" ]]; then
  echo "[ERROR] Could not resolve OPENSEARCH_ENDPOINT. Set the env var or deploy first." >&2
  exit 1
fi

# Strip trailing slash and protocol for awscurl
ENDPOINT="${OPENSEARCH_ENDPOINT%/}"
echo "[INFO] Using OpenSearch endpoint: ${ENDPOINT}"

# ── Check awscurl availability ────────────────────────────────────────────────

if ! command -v awscurl &>/dev/null; then
  echo "[ERROR] awscurl not found. Install it with: pip install awscurl" >&2
  exit 1
fi

# ── Helper: authenticated PUT/POST ────────────────────────────────────────────

aoss_put() {
  local path="$1"
  local body="$2"
  awscurl --service aoss --region "${REGION}" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d "${body}" \
    "${ENDPOINT}${path}"
}

aoss_post() {
  local path="$1"
  local content_type="${2:-application/json}"
  local data_flag="${3:--d}"
  local data="${4:-}"
  if [[ "${data_flag}" == "--data-binary" ]]; then
    awscurl --service aoss --region "${REGION}" \
      -X POST \
      -H "Content-Type: ${content_type}" \
      --data-binary "${data}" \
      "${ENDPOINT}${path}"
  else
    awscurl --service aoss --region "${REGION}" \
      -X POST \
      -H "Content-Type: ${content_type}" \
      -d "${data}" \
      "${ENDPOINT}${path}"
  fi
}

# ── Step 1: Create anomalies-* index template ──────────────────────────────────

echo ""
echo "[INFO] Creating anomalies-* index template..."

INDEX_TEMPLATE='{
  "index_patterns": ["anomalies-*"],
  "template": {
    "mappings": {
      "properties": {
        "timestamp":         {"type": "date"},
        "anomaly_id":        {"type": "keyword"},
        "account_id":        {"type": "keyword"},
        "service":           {"type": "keyword"},
        "rule_type":         {"type": "keyword"},
        "severity":          {"type": "keyword"},
        "detection_method":  {"type": "keyword"},
        "status":            {"type": "keyword"},
        "environment":       {"type": "keyword"},
        "description":       {"type": "text"},
        "details": {
          "type": "object",
          "properties": {
            "z_score":           {"type": "float"},
            "current_value":     {"type": "float"},
            "error_rate":        {"type": "float"},
            "threshold":         {"type": "float"},
            "current_p95_ms":    {"type": "float"},
            "baseline_p95_ms":   {"type": "float"},
            "multiplier":        {"type": "float"},
            "drop_ratio":        {"type": "float"},
            "total_logs":        {"type": "long"},
            "error_logs":        {"type": "long"},
            "recent_count":      {"type": "long"},
            "previous_count":    {"type": "long"},
            "metric_field":      {"type": "keyword"},
            "policy_id":         {"type": "keyword"},
            "sensitivity":       {"type": "keyword"},
            "event_name":        {"type": "keyword"}
          }
        }
      }
    }
  }
}'

TEMPLATE_RESPONSE=$(aoss_put "/_index_template/anomalies-template" "${INDEX_TEMPLATE}")
echo "[INFO] Index template response: ${TEMPLATE_RESPONSE}"

if echo "${TEMPLATE_RESPONSE}" | grep -q '"acknowledged":true'; then
  echo "[OK] anomalies-* index template created successfully."
else
  echo "[WARN] Unexpected response from index template PUT. Check above output." >&2
fi

# ── Step 2: Import dashboard saved objects ─────────────────────────────────────

echo ""
echo "[INFO] Importing dashboard saved objects from ${NDJSON_FILE}..."

if [[ ! -f "${NDJSON_FILE}" ]]; then
  echo "[ERROR] NDJSON file not found: ${NDJSON_FILE}" >&2
  exit 1
fi

IMPORT_RESPONSE=$(awscurl --service aoss --region "${REGION}" \
  -X POST \
  -H "osd-xsrf: true" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@${NDJSON_FILE};type=application/ndjson" \
  "${ENDPOINT}/_dashboards/api/saved_objects/_import?overwrite=true")

echo "[INFO] Import response: ${IMPORT_RESPONSE}"

if echo "${IMPORT_RESPONSE}" | grep -q '"success":true'; then
  echo "[OK] Dashboard saved objects imported successfully."
elif echo "${IMPORT_RESPONSE}" | grep -q '"successCount"'; then
  SUCCESS_COUNT=$(echo "${IMPORT_RESPONSE}" | grep -o '"successCount":[0-9]*' | grep -o '[0-9]*')
  echo "[OK] Imported ${SUCCESS_COUNT} saved objects."
else
  echo "[WARN] Import may have failed or partially succeeded. Review response above." >&2
  exit 1
fi

echo ""
echo "[DONE] OpenSearch Dashboards setup complete for environment: ${ENVIRONMENT}"
echo "       Navigate to: ${ENDPOINT}/_dashboards"
echo "       Dashboards available:"
echo "         - Unified Incident Timeline    → #/view/unified-incident-timeline"
echo "         - Anomaly Detection Results    → #/view/anomaly-detection-results"
echo "         - RCA Evidence Explorer        → #/view/rca-evidence-explorer"
