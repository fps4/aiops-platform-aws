# ADR-002: Apache Trino Not Selected as Observability Query Layer

**Status**: Accepted
**Date**: 2026-02-23
**Deciders**: Platform team

---

## Context

After selecting ClickHouse + Grafana (ADR-001), a follow-up question was raised: could **Apache Trino** with **S3 as storage** (a data lakehouse / medallion architecture) serve as the observability backend instead? The proposal was to structure S3 into data zones and place Trino on top as the query engine, avoiding a separately managed database altogether.

The architecture would use a medallion pattern:

```
Bronze  — S3 raw logs (already written by Kinesis Firehose today)
Silver  — S3 normalized logs as Apache Iceberg table (written by log-normalizer Lambda)
Gold    — S3 anomalies / pre-aggregated metrics as Iceberg table
Trino   — query engine across all zones (self-managed on ECS, or AWS Athena)
```

This is a well-established pattern in data engineering. The question is whether it fits the specific requirements of a real-time anomaly detection platform.

---

## What Trino Is

Trino is a distributed SQL query engine, not a database. It does not store data. It federates queries over external storage backends — S3/Iceberg, Hive, DynamoDB, PostgreSQL, Kafka, and others — via a connector model. When paired with S3 and a table format (Apache Iceberg, Delta Lake, or Hudi), it acts as the compute layer of a data lakehouse.

AWS Athena is Trino under the hood, managed by AWS. Using Athena eliminates the need to operate a Trino cluster, which removes a significant portion of the operational objection.

---

## Requirements Against Which Trino Was Evaluated

The anomaly detection pipeline has specific requirements that drove this evaluation:

1. **Write frequency**: The log-normalizer Lambda flushes normalized log batches every ~60 seconds.
2. **Query freshness**: The statistical detector (Fargate, every 5 min) and rule-based detector (Lambda, every 5 min) query the last 7 days of data. Data must be queryable within 1–2 minutes of ingestion for detection to be meaningful.
3. **Query shape**: Aggregations over a 7-day window — `avg()`, `quantile(0.95)()`, `countIf()`, `GROUP BY toStartOfInterval(timestamp, 5 MINUTE)`. Not ad-hoc exploration; a fixed, repeated workload.
4. **Grafana integration**: Pre-built dashboards with time-series panels and variable-based filtering.

---

## Problems with Trino + S3 for This Use Case

### 1. The small files problem

The log-normalizer Lambda writes approximately once per minute. Each flush creates one or more small Parquet files in the Iceberg Silver table. Over 24 hours, a single day-partition accumulates ~1,440 files.

Trino must open a file handle for each data file it reads. At 1,440 files per day partition, a 7-day query reads up to ~10,000 files. File-open overhead alone degrades query latency from milliseconds to tens of seconds — well past the acceptable threshold for a detection loop running every 5 minutes.

This is a known limitation of streaming writes into object-storage table formats. The standard mitigation is **compaction**: a background job (Spark on EMR, AWS Glue ETL, or Iceberg's `rewrite_data_files` procedure) that merges small files into larger ones on a regular schedule. Compaction works but:

- Adds another scheduled job to operate and monitor.
- Creates a window where pre-compaction queries are slow and post-compaction queries are fast, making query latency non-deterministic.
- Must run at a cadence that keeps the file count manageable (every 15–30 min to stay ahead of Lambda writes).

### 2. Write-to-query latency

ClickHouse provides **immediate consistency**: a Lambda insert is queryable by the next detection run with no intermediate steps.

The Trino + S3 path adds latency at multiple points:

```
Lambda writes Parquet → S3 PUT → Iceberg manifest updated → Trino reads manifest → queries files
```

Each step is individually fast (seconds), but the compaction requirement means detection queries either run against a fragmented file set (slow) or wait for compaction (stale). For a 5-minute detection cadence, a 2–4 minute compaction lag is a meaningful fraction of the window.

### 3. Trino is compute, not storage — it still needs infrastructure

Self-managed Trino requires a coordinator node and at least one worker node. On ECS, that is two always-on Fargate tasks or EC2 instances. AWS Athena removes this burden, but Athena introduces per-query costs at $5/TB scanned. For the detection loop running 12 times per hour, 24 hours a day, querying 7 days of logs, per-query scan costs accumulate and are harder to predict than a fixed EC2 instance cost.

### 4. No native high-frequency insert path

ClickHouse's MergeTree engine is specifically designed for high-frequency small inserts; it buffers, sorts, and merges data files in the background without application involvement. Iceberg on S3 has no equivalent. Every Lambda write is a discrete file commit. Handling this at ingestion frequency requires either accepting file fragmentation or adding buffering infrastructure (Kafka, Kinesis → batch writer) that is not present in the current architecture.

### 5. Grafana integration

The `grafana-clickhouse-datasource` plugin has first-class support for ClickHouse's time-series functions. For Athena/Trino, Grafana uses a generic JDBC datasource or the Athena plugin, both of which require hand-written SQL for every panel and have weaker time-series query builder support.

---

## Where Trino + S3 Would Be the Right Choice

This evaluation is specific to the hot-path detection workload. Trino + S3 is the correct architecture for:

| Use case | Fit |
|---|---|
| Historical log analysis over months of data | ✓ S3 is cheaper than EBS at scale |
| Cross-source queries (S3 logs + DynamoDB + RDS + cost data) | ✓ Trino federation |
| Phase 2 NL-to-SQL chat agent querying the full log archive | ✓ Athena + ANSI SQL |
| Ad-hoc investigation by SREs, not a scheduled loop | ✓ Per-query Athena cost model acceptable |
| Batch anomaly reports over 30/90-day windows | ✓ Iceberg partitioning handles large scans well |

---

## Decision

**Trino is not selected as the primary observability query layer.** The small files problem, compaction requirement, and write-to-query latency make it unsuitable for a detection loop running every 5 minutes against data that must be current within 1–2 minutes of ingestion. ClickHouse remains the correct choice for the hot path (ADR-001).

**However, a hybrid architecture is the recommended long-term target:**

- **ClickHouse** (hot path): real-time detection, last 7 days, sub-second queries
- **S3 + Athena** (cold path): historical analysis, Phase 2 NL agent, ad-hoc SRE queries over the full archive

The Firehose pipeline already writes raw logs to S3 Bronze. A nightly AWS Glue ETL job compacting those files into a clean Iceberg Silver table would provide a queryable historical archive at no additional ingestion cost — the Lambda pipeline does not need to change. Detection agents continue hitting ClickHouse. The NL chat agent and historical Grafana panels hit Athena.

---

## Consequences

- No change to the current ClickHouse implementation (ADR-001 stands).
- S3 Bronze zone is already in place via Kinesis Firehose.
- When Phase 2 (NL chat agent) is scoped, evaluate adding Athena + Glue on top of the existing S3 raw zone rather than introducing a new store.
- Revisit ClickHouse vs. Trino hot-path if ingestion volume grows to the point where a single ClickHouse EC2 instance becomes a bottleneck (roughly >500GB/day or >1M inserts/min).
