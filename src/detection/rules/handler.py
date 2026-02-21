"""Rule-based detection Lambda.

Evaluates hard thresholds against current OpenSearch aggregations and writes
anomaly records to DynamoDB when rules are breached.

Trigger: can be invoked by CloudWatch Metric Alarms, EventBridge rules, or
directly by other Lambdas.
"""
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any

import boto3
from boto3.dynamodb.conditions import Attr, Key

try:
    from src.shared.logger import get_logger
    from src.shared.opensearch_client import OpenSearchClient
except ImportError:
    try:
        from shared.logger import get_logger          # type: ignore[no-redef]
        from shared.opensearch_client import OpenSearchClient  # type: ignore[no-redef]
    except ImportError:
        def get_logger(name: str) -> logging.Logger:  # type: ignore[misc]
            logger = logging.getLogger(name)
            if not logger.handlers:
                logger.addHandler(logging.StreamHandler())
                logger.setLevel(logging.INFO)
            return logger
        OpenSearchClient = None  # type: ignore[assignment,misc]

logger = get_logger("rule-detection")

# ─── Rule thresholds (defaults; overridden by policy_store) ───────────────────
DEFAULT_ERROR_RATE_THRESHOLD = 0.05          # 5 %
DEFAULT_ERROR_RATE_WINDOW_MINUTES = 5
DEFAULT_LATENCY_MULTIPLIER = 2.0             # P95 > N× 7-day baseline
DEFAULT_LATENCY_WINDOW_MINUTES = 3
DEFAULT_TRAFFIC_DROP_THRESHOLD = 0.80        # 80 % drop
DEFAULT_TRAFFIC_DROP_WINDOW_MINUTES = 10
DEFAULT_COOLDOWN_SECONDS = 300

_dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "eu-central-1"))
_opensearch = None


def _get_opensearch():
    global _opensearch
    if _opensearch is None:
        if OpenSearchClient is None:
            raise RuntimeError("OpenSearchClient is not available")
        _opensearch = OpenSearchClient()
    return _opensearch


def _anomalies_table():
    return _dynamodb.Table(os.environ["DYNAMODB_ANOMALIES_TABLE"])


def _policy_store_table():
    env_table = os.environ.get("DYNAMODB_POLICY_TABLE", "")
    if not env_table:
        env_table = os.environ["DYNAMODB_ANOMALIES_TABLE"].replace("anomalies", "policy-store")
    return _dynamodb.Table(env_table)


def _load_thresholds(service: str) -> dict[str, Any]:
    """Load per-service thresholds from DynamoDB policy_store."""
    defaults: dict[str, Any] = {
        "error_rate_threshold": DEFAULT_ERROR_RATE_THRESHOLD,
        "error_rate_window_minutes": DEFAULT_ERROR_RATE_WINDOW_MINUTES,
        "latency_multiplier": DEFAULT_LATENCY_MULTIPLIER,
        "latency_window_minutes": DEFAULT_LATENCY_WINDOW_MINUTES,
        "traffic_drop_threshold": DEFAULT_TRAFFIC_DROP_THRESHOLD,
        "traffic_drop_window_minutes": DEFAULT_TRAFFIC_DROP_WINDOW_MINUTES,
        "cooldown_seconds": DEFAULT_COOLDOWN_SECONDS,
    }
    try:
        resp = _policy_store_table().get_item(Key={"policy_id": f"rule:{service}"})
        item = resp.get("Item", {})
        if item:
            defaults.update({k: v for k, v in item.items() if k in defaults})
    except Exception as exc:  # noqa: BLE001
        logger.warning("Could not load policy for %s: %s", service, exc)
    return defaults


def _is_in_cooldown(table, rule_type: str, service: str, cooldown_seconds: int) -> bool:
    """Return True if an anomaly of this type was already written within the cooldown window."""
    now_ts = datetime.now(timezone.utc)
    cutoff_ts = now_ts.timestamp() - cooldown_seconds
    cutoff_iso = datetime.fromtimestamp(cutoff_ts, tz=timezone.utc).isoformat()

    try:
        resp = table.query(
            IndexName="ServiceIndex",
            KeyConditionExpression=Key("service").eq(service) & Key("timestamp").gt(cutoff_iso),
            FilterExpression=Attr("rule_type").eq(rule_type),
            Limit=1,
        )
        return len(resp.get("Items", [])) > 0
    except Exception as exc:  # noqa: BLE001
        logger.warning("Cooldown check failed: %s", exc)
        return False


def _write_anomaly(
    table,
    rule_type: str,
    service: str,
    account_id: str,
    description: str,
    severity: str,
    details: dict[str, Any],
) -> dict[str, Any]:
    """Write a new anomaly record to DynamoDB."""
    now = datetime.now(timezone.utc)
    anomaly_id = str(uuid.uuid4())
    item: dict[str, Any] = {
        "anomaly_id": anomaly_id,
        "timestamp": now.isoformat(),
        "account_id": account_id,
        "service": service,
        "rule_type": rule_type,
        "severity": severity,
        "description": description,
        "details": details,
        "status": "open",
        "detection_method": "rule-based",
        "environment": os.environ.get("ENVIRONMENT", "unknown"),
        "ttl": int(now.timestamp()) + 7 * 24 * 3600,
    }
    table.put_item(Item=item)
    logger.info(
        "Anomaly written: id=%s type=%s service=%s severity=%s",
        anomaly_id, rule_type, service, severity,
    )
    return item


# ─── Rule evaluators ──────────────────────────────────────────────────────────

def _check_error_rate(
    opensearch,
    table,
    service: str,
    account_id: str,
    thresholds: dict[str, Any],
) -> dict[str, Any] | None:
    """Check if error rate exceeds threshold."""
    window = thresholds["error_rate_window_minutes"]
    threshold = thresholds["error_rate_threshold"]
    cooldown = thresholds["cooldown_seconds"]

    query = {
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"service": service}},
                    {"range": {"timestamp": {"gte": f"now-{window}m"}}},
                ]
            }
        },
        "aggs": {
            "total": {"value_count": {"field": "timestamp"}},
            "errors": {
                "filter": {"terms": {"log_level": ["ERROR", "CRITICAL"]}},
                "aggs": {"count": {"value_count": {"field": "timestamp"}}},
            },
        },
    }

    try:
        resp = opensearch.search(index=f"logs-{service}-*", body=query)
        aggs = resp.get("aggregations", {})
        total = aggs.get("total", {}).get("value", 0)
        error_count = aggs.get("errors", {}).get("count", {}).get("value", 0)
    except Exception as exc:  # noqa: BLE001
        logger.error("Error rate query failed for %s: %s", service, exc)
        return None

    if total == 0:
        return None

    error_rate = error_count / total
    if error_rate <= threshold:
        return None

    if _is_in_cooldown(table, "error_rate", service, cooldown):
        logger.info("Error rate anomaly suppressed by cooldown for %s", service)
        return None

    return _write_anomaly(
        table=table,
        rule_type="error_rate",
        service=service,
        account_id=account_id,
        description=f"Error rate {error_rate:.1%} exceeds threshold {threshold:.1%}",
        severity="high",
        details={
            "error_rate": error_rate,
            "threshold": threshold,
            "total_logs": total,
            "error_logs": error_count,
        },
    )


def _check_latency_regression(
    opensearch,
    table,
    service: str,
    account_id: str,
    thresholds: dict[str, Any],
) -> dict[str, Any] | None:
    """Check if P95 latency exceeds N× the 7-day baseline."""
    window = thresholds["latency_window_minutes"]
    multiplier = thresholds["latency_multiplier"]
    cooldown = thresholds["cooldown_seconds"]

    current_query = {
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"service": service}},
                    {"range": {"timestamp": {"gte": f"now-{window}m"}}},
                ]
            }
        },
        "aggs": {
            "p95_latency": {"percentiles": {"field": "duration_ms", "percents": [95]}}
        },
    }

    baseline_query = {
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"service": service}},
                    {"range": {"timestamp": {"gte": "now-7d", "lt": f"now-{window}m"}}},
                ]
            }
        },
        "aggs": {
            "p95_latency": {"percentiles": {"field": "duration_ms", "percents": [95]}}
        },
    }

    try:
        current_resp = opensearch.search(index=f"logs-{service}-*", body=current_query)
        baseline_resp = opensearch.search(index=f"logs-{service}-*", body=baseline_query)
    except Exception as exc:  # noqa: BLE001
        logger.error("Latency query failed for %s: %s", service, exc)
        return None

    current_p95 = (
        current_resp.get("aggregations", {})
        .get("p95_latency", {})
        .get("values", {})
        .get("95.0")
    )
    baseline_p95 = (
        baseline_resp.get("aggregations", {})
        .get("p95_latency", {})
        .get("values", {})
        .get("95.0")
    )

    if current_p95 is None or baseline_p95 is None or baseline_p95 == 0:
        return None

    if current_p95 <= multiplier * baseline_p95:
        return None

    if _is_in_cooldown(table, "latency_regression", service, cooldown):
        logger.info("Latency anomaly suppressed by cooldown for %s", service)
        return None

    return _write_anomaly(
        table=table,
        rule_type="latency_regression",
        service=service,
        account_id=account_id,
        description=(
            f"P95 latency {current_p95:.0f}ms is "
            f"{current_p95 / baseline_p95:.1f}× the 7-day baseline {baseline_p95:.0f}ms"
        ),
        severity="high",
        details={
            "current_p95_ms": current_p95,
            "baseline_p95_ms": baseline_p95,
            "multiplier": current_p95 / baseline_p95,
        },
    )


def _check_traffic_drop(
    opensearch,
    table,
    service: str,
    account_id: str,
    thresholds: dict[str, Any],
) -> dict[str, Any] | None:
    """Check if request volume has dropped by more than the threshold."""
    window = thresholds["traffic_drop_window_minutes"]
    drop_threshold = thresholds["traffic_drop_threshold"]
    cooldown = thresholds["cooldown_seconds"]

    query = {
        "size": 0,
        "query": {"bool": {"must": [{"term": {"service": service}}]}},
        "aggs": {
            "recent": {
                "filter": {"range": {"timestamp": {"gte": f"now-{window}m"}}},
                "aggs": {"count": {"value_count": {"field": "timestamp"}}},
            },
            "previous": {
                "filter": {"range": {"timestamp": {"gte": f"now-{window * 2}m", "lt": f"now-{window}m"}}},
                "aggs": {"count": {"value_count": {"field": "timestamp"}}},
            },
        },
    }

    try:
        resp = opensearch.search(index=f"logs-{service}-*", body=query)
        aggs = resp.get("aggregations", {})
        recent_count = aggs.get("recent", {}).get("count", {}).get("value", 0)
        previous_count = aggs.get("previous", {}).get("count", {}).get("value", 0)
    except Exception as exc:  # noqa: BLE001
        logger.error("Traffic drop query failed for %s: %s", service, exc)
        return None

    if previous_count == 0:
        return None

    drop_ratio = (previous_count - recent_count) / previous_count
    if drop_ratio <= drop_threshold:
        return None

    if _is_in_cooldown(table, "traffic_drop", service, cooldown):
        logger.info("Traffic drop anomaly suppressed by cooldown for %s", service)
        return None

    return _write_anomaly(
        table=table,
        rule_type="traffic_drop",
        service=service,
        account_id=account_id,
        description=(
            f"Traffic dropped {drop_ratio:.1%} from {previous_count} "
            f"to {recent_count} requests in {window} minutes"
        ),
        severity="critical",
        details={
            "recent_count": recent_count,
            "previous_count": previous_count,
            "drop_ratio": drop_ratio,
        },
    )


def _check_iam_policy_changes(
    opensearch,
    table,
    account_id: str,
    thresholds: dict[str, Any],
) -> list[dict[str, Any]]:
    """Detect IAM policy changes from CloudTrail events in OpenSearch."""
    cooldown = thresholds["cooldown_seconds"]
    anomalies = []

    query = {
        "size": 10,
        "query": {
            "bool": {
                "must": [
                    {
                        "terms": {
                            "message": [
                                "CreatePolicy",
                                "DeletePolicy",
                                "AttachRolePolicy",
                                "DetachRolePolicy",
                                "PutRolePolicy",
                                "DeleteRolePolicy",
                            ]
                        }
                    },
                    {"range": {"timestamp": {"gte": "now-15m"}}},
                ]
            }
        },
    }

    try:
        resp = opensearch.search(index="logs-cloudtrail-*", body=query)
        hits = resp.get("hits", {}).get("hits", [])
    except Exception as exc:  # noqa: BLE001
        logger.error("IAM change query failed for account %s: %s", account_id, exc)
        return []

    for hit in hits:
        source = hit.get("_source", {})
        event_name = source.get("message", "IAMChange")

        if _is_in_cooldown(table, f"iam_change:{event_name}", "iam", cooldown):
            continue

        anomaly = _write_anomaly(
            table=table,
            rule_type="iam_policy_change",
            service="iam",
            account_id=account_id,
            description=f"IAM policy change detected: {event_name}",
            severity="medium",
            details={"event_name": event_name, "source_event": source},
        )
        anomalies.append(anomaly)

    return anomalies


# ─── Lambda entry point ───────────────────────────────────────────────────────

def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Evaluate all detection rules and write anomalies to DynamoDB.

    Args:
        event: Invocation event. May contain ``services`` and ``account_id``.
        context: Lambda context (unused).

    Returns:
        Summary dict with counts of anomalies detected.
    """
    account_id = event.get("account_id") or os.environ.get("AWS_ACCOUNT_ID", "unknown")
    services = event.get("services", [])

    opensearch = _get_opensearch()
    table = _anomalies_table()

    detected: list[dict[str, Any]] = []

    for service in services:
        thresholds = _load_thresholds(service)

        anomaly = _check_error_rate(opensearch, table, service, account_id, thresholds)
        if anomaly:
            detected.append(anomaly)

        anomaly = _check_latency_regression(opensearch, table, service, account_id, thresholds)
        if anomaly:
            detected.append(anomaly)

        anomaly = _check_traffic_drop(opensearch, table, service, account_id, thresholds)
        if anomaly:
            detected.append(anomaly)

    iam_anomalies = _check_iam_policy_changes(
        opensearch, table, account_id, _load_thresholds("iam")
    )
    detected.extend(iam_anomalies)

    logger.info(
        "Rule detection complete: services=%d anomalies=%d",
        len(services), len(detected),
    )

    return {
        "anomalies_detected": len(detected),
        "anomaly_ids": [a["anomaly_id"] for a in detected],
    }
