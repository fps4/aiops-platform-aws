-- AIOps Platform ClickHouse schema
-- Run once after ClickHouse starts: clickhouse-client < scripts/init-clickhouse-schema.sql

CREATE DATABASE IF NOT EXISTS aiops;

-- Normalized log records (written by log-normalizer Lambda)
CREATE TABLE IF NOT EXISTS aiops.logs
(
    timestamp           DateTime64(3, 'UTC'),
    account_id          LowCardinality(String),
    region              LowCardinality(String),
    service             LowCardinality(String),
    environment         LowCardinality(String),
    log_level           LowCardinality(String),
    message             String,
    deployment_version  String,
    deployment_timestamp String,
    related_events      Array(String),
    -- Numeric metric fields embedded in log records
    duration_ms         Nullable(Float64),
    error_count         Nullable(Float64),
    request_count       Nullable(Float64),
    -- Extra fields not in canonical schema stored as JSON string
    _raw                String DEFAULT '{}'
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (service, timestamp)
TTL timestamp + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Anomaly records (written by rule-detection Lambda and statistical detector)
CREATE TABLE IF NOT EXISTS aiops.anomalies
(
    anomaly_id          String,
    timestamp           DateTime64(3, 'UTC'),
    account_id          LowCardinality(String),
    service             LowCardinality(String),
    rule_type           LowCardinality(String),
    detection_method    LowCardinality(String),
    severity            LowCardinality(String),
    description         String,
    status              LowCardinality(String),
    environment         LowCardinality(String),
    details             String DEFAULT '{}'  -- JSON blob for rule-specific fields
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (service, timestamp)
TTL timestamp + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;
