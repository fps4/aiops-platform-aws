# ADR-004: Tracing and Metrics Strategy — Cloud-Native Backends with OpenTelemetry Instrumentation

**Status**: Accepted  
**Date**: 2026-03-11  
**Deciders**: Platform team

---

## Context

The platform needs first-class telemetry across Lambda, Fargate, and EC2 components for:

- End-to-end request/workflow tracing (ingestion -> detection -> orchestration -> notification)
- Service and business metrics (latency, errors, throughput, anomaly pipeline health)
- Low operational overhead in AWS
- Future portability and vendor flexibility

We evaluated two primary directions: AWS-native-only instrumentation vs OpenTelemetry-first.

---

## Options Considered

### Option A: AWS-native only (CloudWatch metrics + X-Ray SDKs)

Use CloudWatch Embedded Metrics Format (EMF), CloudWatch Alarms, and X-Ray SDK directly in services.

**Pros**
- Minimal moving parts in AWS
- Straightforward IAM and managed service integration
- Good fit for Lambda-heavy systems

**Cons**
- Instrumentation is vendor-specific and harder to reuse elsewhere
- Less consistent telemetry model across runtimes/languages
- Future backend migration requires code rewrites

### Option B: OpenTelemetry + self-managed telemetry stack

Use OTEL SDK/Collector with self-managed Prometheus/Tempo/Jaeger (or equivalent).

**Pros**
- Maximum portability and open standards end-to-end
- Rich ecosystem and flexible backend routing

**Cons**
- Higher operational complexity for this team/stage
- Additional infrastructure to run, secure, and scale
- Slower delivery for Phase 1 goals

### Option C: OpenTelemetry instrumentation + AWS managed backends (ADOT pattern)

Use OpenTelemetry SDK conventions and ADOT Collector where needed; export traces to X-Ray and metrics to CloudWatch (and optionally AMP for Prometheus-style metrics).

**Pros**
- Cloud-native operations with low overhead
- Standards-based instrumentation and semantic conventions
- Keeps migration path open while optimizing for AWS now
- Works across Lambda, Fargate, and EC2 consistently

**Cons**
- Some AWS-specific exporter/config details remain
- Requires initial collector/exporter setup discipline

---

## Decision

Adopt **Option C**:

- **Instrumentation standard**: OpenTelemetry (OTEL SDK + semantic conventions)
- **Tracing backend (Phase 1)**: AWS X-Ray
- **Metrics backend (Phase 1)**: CloudWatch (with EMF/OTEL exporters)
- **Optional metrics expansion**: Amazon Managed Service for Prometheus (AMP) for advanced PromQL use cases

This gives cloud-native simplicity now and avoids lock-in at the instrumentation layer.

---

## Implementation Guidelines

1. **Trace context propagation**
   - Propagate trace context across Lambda invocations and async boundaries.
   - Include domain correlation attributes: `anomaly_id`, `workflow_id`, `account_id`, `service`, `environment`.

2. **Lambda telemetry**
   - Use ADOT Lambda layer / OTEL SDK configuration.
   - Export traces to X-Ray.
   - Emit key custom metrics: ingestion lag, detector runtime, agent stage latency, alert delivery status.

3. **Fargate telemetry**
   - Run ADOT Collector sidecar for OTLP ingestion/export.
   - Export traces to X-Ray and metrics to CloudWatch or AMP.

4. **EC2 telemetry (ClickHouse/Grafana hosts and supporting services)**
   - Use CloudWatch Agent for host metrics/logs.
   - Add OTEL Collector agent only where app-level tracing is required.

5. **Metric taxonomy**
   - Standardize dimensions: `env`, `service`, `component`, `account_scope`.
   - Track RED metrics (rate, errors, duration) per critical component.
   - Add pipeline SLO metrics (time-to-detect, time-to-RCA, time-to-alert).

6. **Alerting**
   - CloudWatch alarms for error budget burn, pipeline lag, detector failures, and notification failures.

---

## Consequences

### Positive
- Strong observability with managed AWS reliability.
- Lower delivery risk for Phase 1.
- Future portability preserved by OTEL instrumentation choice.

### Trade-offs
- Not fully backend-agnostic at export layer in Phase 1.
- Requires governance to keep telemetry naming and attributes consistent.

---

## Revisit Triggers

Re-open this decision if:

- Multi-cloud telemetry becomes near-term scope
- CloudWatch/X-Ray cost or query UX becomes limiting
- Need for advanced cross-service PromQL/trace analytics exceeds current backend fit

If triggered, keep OTEL instrumentation unchanged and swap exporters/backends incrementally.

