# Data Flow Example (End-to-End)

**Scenario**: API Gateway latency spike caused by a slow database query introduced by a new deployment.

---

## Step 1: Ingestion (T+0 seconds)

- API Gateway logs show 500ms+ response times
- CloudWatch Logs → Subscription Filter → Kinesis Firehose → log-normalizer Lambda

## Step 2: Normalization (T+5 seconds)

- Lambda parses logs, enriches with deployment metadata
- Writes canonical record to S3 (raw) and ClickHouse (indexed):
  ```json
  {"timestamp": "...", "service": "api-gateway", "p95_latency_ms": 1200, ...}
  ```

## Step 3: Detection (next scheduled run, within 5 minutes)

- Fargate statistical detector queries ClickHouse:
  ```sql
  SELECT avg(p95_latency_ms) FROM aiops.metrics
  WHERE service = 'api-gateway' AND timestamp >= now() - INTERVAL 7 DAY
  ```
- Baseline = 150ms, current = 1200ms, z-score = 5.2 → **ANOMALY**
- Writes anomaly to DynamoDB `anomalies` table → triggers orchestrator Lambda via DynamoDB Stream

## Step 4: Agentic Workflow (T+30s to T+2min)

1. **Detection Agent**: Checks for duplicate anomalies — none found, passes through
2. **Correlation Agent**: Queries events table, finds deployment `v2.3.1` at T−15min
3. **Historical Compare**: Searches past incidents, finds similar latency spike (INC-2024-045)
4. **RCA Agent**: Calls Bedrock Claude with full context:
   - Input: anomaly + deployment event + similar past incident + error logs
   - Output: `"Probable cause: New deployment introduced slow query. Confidence: High (85%). Evidence: Deployment timestamp aligns with spike. Error logs show DB timeouts."`
5. **Recommendation Agent**: Maps to runbook: "Rollback deployment or optimize query"

## Step 5: Alert (T+2min)

- Slack notifier formats Block Kit payload (RCA summary + Grafana deep-link)
- Posts to `#aiops-alerts`
- Engineer clicks link → lands on pre-filtered Grafana dashboard showing logs, metrics, and deployment event

## Step 6: Investigation (T+3min)

- Engineer reviews Grafana dashboard with ClickHouse-backed panels
- Confirms RCA hypothesis by drilling into slow query logs
- Executes rollback or query optimization

---

**Total latency: anomaly → Slack alert in engineer's hands = < 7 minutes**
(up to 5 min detection interval + ~2 min agentic pipeline)
