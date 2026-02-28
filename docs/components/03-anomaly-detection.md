# Anomaly Detection

Two complementary detection mechanisms write to the same DynamoDB `anomalies` table.

---

## Statistical Detection (Fargate Scheduled Task)

A single Fargate container runs every 5 minutes via EventBridge Scheduler → ECS RunTask. Each run iterates over all monitored services and metrics, queries ClickHouse for historical baselines, runs detection algorithms, and writes anomalies to DynamoDB.

### Why Fargate over Lambda

- **Heavy dependencies**: STL (`statsmodels`), PELT (`ruptures`), `numpy`/`scipy` exceed Lambda's 250 MB unzipped limit
- **Batch-oriented**: Detection algorithms need full 7-day windows — periodic batch, not event-driven
- **In-memory efficiency**: Single process iterates all services/metrics, caching ClickHouse connections and shared state within a run
- **No fan-out complexity**: One container processes everything vs orchestrating hundreds of concurrent Lambdas
- **Cost**: ~$1–3/month (256 CPU, 512 MB, runs 1–2 min every 5 min)

### Container Spec

- **Image**: Python 3.13 with `statsmodels`, `ruptures`, `numpy`, `scipy`, `httpx`, `boto3`
- **Resources**: 256 CPU units, 512 MB memory
- **Schedule**: EventBridge Scheduler rule, `rate(5 minutes)`
- **Networking**: Private subnet, HTTPS egress to ClickHouse HTTP API and DynamoDB
- **Timeout**: 5 minutes (must complete before next scheduled run)

### Algorithms

- **Seasonality Baseline**: STL decomposition (seasonal-trend decomposition)
- **Change-Point Detection**: PELT (Pruned Exact Linear Time) algorithm
- **Scoring**: Z-score with sliding window, EWMA (Exponentially Weighted Moving Average)

### Metrics Analyzed

- Error rate (errors per minute by service)
- Latency percentiles (p50, p95, p99)
- Request rate (traffic volume)
- Resource utilization (CPU, memory, disk I/O)

### Detection Loop (pseudo-code)

```python
def run_detection():
    policies = load_policies_from_dynamodb()
    ch_url = os.environ["CLICKHOUSE_HTTP_URL"]  # http://<private-ip>:8123

    for policy in policies:
        for metric in policy["metrics"]:
            # Query ClickHouse for 7-day baseline
            baseline_sql = f"""
                SELECT toStartOfMinute(timestamp) AS ts, avg({metric}) AS value
                FROM aiops.metrics
                WHERE service = '{policy['service']}'
                  AND timestamp >= now() - INTERVAL {policy['baseline_window']}
                GROUP BY ts ORDER BY ts
                FORMAT JSONEachRow
            """
            baseline_data = [
                row["value"]
                for row in httpx.post(ch_url, content=baseline_sql).json()
            ]

            # Run STL decomposition
            trend, seasonal, residual = stl_decompose(baseline_data)

            # Score current value against baseline
            current_sql = f"""
                SELECT avg({metric}) AS value
                FROM aiops.metrics
                WHERE service = '{policy['service']}'
                  AND timestamp >= now() - INTERVAL 5 MINUTE
                FORMAT JSONEachRow
            """
            current = httpx.post(ch_url, content=current_sql).json()[0]["value"]
            z_score = compute_z_score(current, residual)

            # Check for change-points
            change_points = pelt_detect(baseline_data)

            if z_score > policy["sensitivity_threshold"]:
                anomaly = build_anomaly_object(policy, metric, current, z_score, change_points)
                write_to_dynamodb(anomaly)
```

### Policy Configuration (per detection policy)

```yaml
detection:
  baseline_window: 7d        # Compare to last 7 days
  sensitivity: high          # low=4σ, medium=3σ, high=2σ
  min_deviation_pct: 50      # Ignore <50% changes
  cooldown_minutes: 30       # Suppress similar alerts for 30 min
```

### Output: Anomaly Object

```json
{
  "anomaly_id": "anom-abc123",
  "timestamp": "2026-02-14T10:00:00Z",
  "signal": "p95_latency_ms",
  "service": "api-gateway",
  "account_id": "123456789012",
  "current_value": 1200,
  "baseline_value": 150,
  "deviation_pct": 700,
  "z_score": 5.2,
  "confidence": "high"
}
```

---

## Rule-Based Guardrails (Lambda)

Hard thresholds that fire without needing a statistical baseline:

- Error rate > 5% for 5 consecutive minutes
- P95 latency > 2× baseline for 3 minutes
- Traffic drop > 80% within 10 minutes (canary failure)
- Security: IAM policy changes, S3 bucket public access

**Output**: Same anomaly object format (`confidence = "rule_based"`).
