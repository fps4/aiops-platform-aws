# Storage

All storage is in the Central Observability Account (eu-central-1).

## Signal → Storage Mapping

| Signal           | Storage                  | Retention          | Purpose                               |
|------------------|--------------------------|--------------------|---------------------------------------|
| **Raw Logs**     | S3 (Glacier after 7d)    | 90 days (config)   | Audit, replay, cost optimization      |
| **Indexed Logs** | ClickHouse (EC2/systemd) | 90 days (config)   | Search, visualization, alerting       |
| **Metrics**      | ClickHouse (EC2/systemd) | 90 days (config)   | Time-series aggregations, baselines   |
| **Events**       | DynamoDB                 | 90 days (TTL)      | Correlation, audit trail              |
| **Anomalies**    | DynamoDB                 | 90 days (TTL)      | RCA workflow input, dashboards        |
| **Agent State**  | DynamoDB                 | 30 days (TTL)      | Workflow orchestration, retries       |
| **Audit Logs**   | S3 + Athena              | 1 year             | AI prompt/response trail              |

## Canonical Log Schema

All logs are normalized to this JSON structure by the log-normalizer Lambda before being written to ClickHouse and S3:

```json
{
  "timestamp": "2026-02-14T10:00:00Z",
  "account_id": "123456789012",
  "region": "eu-central-1",
  "service": "api-gateway",
  "environment": "prod",
  "log_level": "ERROR",
  "message": "Database connection timeout",
  "deployment_version": "v2.3.1",
  "deployment_timestamp": "2026-02-14T09:15:00Z",
  "related_events": ["deploy-abc123", "autoscale-def456"]
}
```

> **Rule**: Never modify this schema without running an `ALTER TABLE aiops.logs ADD COLUMN ...` migration first. See `scripts/init-clickhouse-schema.sql`.

## Enrichment Pipeline (Lambda)

1. Parse raw logs into canonical schema
2. Extract `account_id`, `region`, `service` from log metadata
3. Look up deployment version from DynamoDB (deployment event store)
4. Add environment tag from AWS Tags API
5. Write to ClickHouse HTTP API (port 8123) + S3
