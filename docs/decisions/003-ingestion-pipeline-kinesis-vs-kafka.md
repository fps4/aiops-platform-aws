# ADR-003: Ingestion Backbone — Kinesis Firehose + Lambda vs Kafka-Centric Pipeline

**Status**: Accepted (Phase 1 / POC baseline)  
**Date**: 2026-03-11  
**Deciders**: Platform team

---

## Context

We need a durable, scalable ingestion backbone for multi-account AWS signals that supports:

- CloudWatch Logs/CloudTrail intake from many accounts
- Canonical normalization before analytics and agentic RCA
- Dual persistence requirements:
  - Raw immutable archive in S3
  - Query-ready data in ClickHouse
- Low operational overhead for POC and Phase 1

Two candidate patterns were evaluated:

1. **AWS-native path (current)**: `Kinesis Firehose -> Lambda normalizer -> S3 + ClickHouse`
2. **Kafka-centric path**: `Kafka/MSK -> ClickHouse + separate sink/process to S3`

---

## Option A: Kinesis Firehose -> Lambda -> S3 + ClickHouse

### Pros

- **Lowest operational burden**: no broker cluster operations, partition rebalancing, or Kafka Connect fleet management.
- **AWS-native integration**: straightforward CloudWatch/CloudTrail ingestion and IAM-first access model.
- **Fast delivery for POC/Phase 1**: fewer moving parts and faster troubleshooting.
- **Built-in buffering/retry semantics** in Firehose reduce custom plumbing.
- **Natural fit for current architecture** (serverless-first control plane with Lambda orchestration).
- **Clear raw-data retention path** with S3 as first-class sink.

### Cons

- **Less flexible stream semantics** than Kafka (limited replay and consumer-group patterns).
- **At-least-once delivery characteristics** require deduplication strategy downstream.
- **Transformation fan-out is less composable** than Kafka topic + Connect ecosystem.
- **Potential Lambda ingestion bottleneck** if ClickHouse writes are not tuned.
- **More AWS lock-in** than a Kafka abstraction.

---

## Option B: Kafka -> ClickHouse + separate sink to S3

### Pros

- **Strong event-log model**: replay, backfill, and multi-consumer pipelines are first-class.
- **Better decoupling** between producers and consumers at high scale.
- **Richer ecosystem** (Connect, Schema Registry, stream processors) for advanced evolution.
- **Good fit for multi-cloud/hybrid futures** where AWS-native assumptions may weaken.

### Cons

- **Higher platform complexity**: brokers, partitions, retention, upgrades, Connect, ACLs, and observability.
- **Higher steady-state cost** for POC/early phase relative to managed Firehose-centric flow.
- **More integration work** from AWS-native sources (CloudWatch/CloudTrail) into Kafka.
- **Dual-sink implementation complexity** (ClickHouse + S3) and stronger exactly-once/idempotency design burden.
- **Operational risk for small team** during early product validation.

---

## Decision

Adopt **Option A (`Kinesis Firehose -> Lambda normalizer -> S3 + ClickHouse`)** as the baseline for **POC and Phase 1**.

Rationale:

1. It best matches current product priorities: speed of delivery, operational simplicity, and AWS-native alignment.
2. It preserves required outcomes (raw archival + analytics-ready store + agentic pipeline input) with minimal platform overhead.
3. The incremental value of Kafka is currently outweighed by complexity and operational cost for early-stage scope.

---

## Consequences

### Positive

- Faster implementation and easier operations for current team size.
- Reduced failure surface in the ingestion/control-plane boundary.
- Strong alignment with existing Terraform and Lambda-centric architecture.

### Negative / trade-offs

- Limited replay/fan-out sophistication versus Kafka event-log approach.
- Need explicit idempotency and dedupe practices in normalization and ClickHouse writes.
- Future migration effort if requirements shift to high-volume multi-consumer streaming.

---

## Guardrails and revisit triggers

Re-open this decision if any of the following occur:

- Need for many independent near-real-time consumers over the same stream.
- Sustained throughput where Lambda-mediated ClickHouse ingestion becomes a bottleneck.
- Hard replay/backfill requirements beyond practical Firehose workflow limits.
- Multi-cloud/hybrid ingestion strategy becomes a near-term requirement.

If triggered, evaluate a staged evolution:
`Firehose baseline -> bridge topics -> Kafka/MSK primary backbone`, while preserving S3 raw retention and ClickHouse query semantics.

