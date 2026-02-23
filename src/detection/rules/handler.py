"""Rule-based detection Lambda.

Evaluates hard thresholds against current ClickHouse aggregations and writes
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
    from src.shared.clickhouse_client import ClickHouseClient
except ImportError:
    try:
        from shared.logger import get_logger          # type: ignore[no-redef]
        from shared.clickhouse_client import ClickHouseClient  # type: ignore[no-redef]
    except ImportError:
        def get_logger(name: str) -> logging.Logger:  # type: ignore[misc]
            logger = logging.getLogger(name)
            if not logger.handlers:
                logger.addHandler(logging.StreamHandler())
                logger.setLevel(logging.INFO)
            return logger
        ClickHouseClient = None  # type: ignore[assignment,misc]

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
_clickhouse = None


def _get_clickhouse():
    global _clickhouse
    if _clickhouse is None:
        if ClickHouseClient is None:
            raise RuntimeError("ClickHouseClient is not available")
        _clickhouse = ClickHouseClient()
    return _clickhouse


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


def _insert_anomaly_to_clickhouse(ch, anomaly: dict[str, Any]) -> None:
    """Insert an anomaly document to ClickHouse. Skips DynamoDB-only fields."""
    exclude = {"ttl", "details"}
    doc = {k: v for k, v in anomaly.items() if k not in exclude}
    doc["details"] = json.dumps(anomaly.get("details", {}))
    try:
        ch.insert("anomalies", [doc])
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "Failed to insert anomaly to ClickHouse: id=%s error=%s",
            anomaly["anomaly_id"], exc,
        )


# ─── Rule evaluators ──────────────────────────────────────────────────────────

def _check_error_rate(
    ch,
    table,
    service: str,
    account_id: str,
    thresholds: dict[str, Any],
) -> dict[str, Any] | None:
    """Check if error rate exceeds threshold."""
    window = thresholds["error_rate_window_minutes"]
    threshold = thresholds["error_rate_threshold"]
    cooldown = thresholds["cooldown_seconds"]

    sql = f"""
        SELECT
            count() AS total,
            countIf(log_level IN ('ERROR', 'CRITICAL')) AS error_count
        FROM aiops.logs
        WHERE service = '{service}'
          AND timestamp >= now() - INTERVAL {window} MINUTE
    """

    try:
        rows = ch.query(sql)
        total = int(rows[0]["total"]) if rows else 0
        error_count = int(rows[0]["error_count"]) if rows else 0
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
    ch,
    table,
    service: str,
    account_id: str,
    thresholds: dict[str, Any],
) -> dict[str, Any] | None:
    """Check if P95 latency exceeds N× the 7-day baseline."""
    window = thresholds["latency_window_minutes"]
    multiplier = thresholds["latency_multiplier"]
    cooldown = thresholds["cooldown_seconds"]

    current_sql = f"""
        SELECT quantile(0.95)(duration_ms) AS p95
        FROM aiops.logs
        WHERE service = '{service}'
          AND timestamp >= now() - INTERVAL {window} MINUTE
          AND duration_ms IS NOT NULL
    """

    baseline_sql = f"""
        SELECT quantile(0.95)(duration_ms) AS p95
        FROM aiops.logs
        WHERE service = '{service}'
          AND timestamp >= now() - INTERVAL 7 DAY
          AND timestamp < now() - INTERVAL {window} MINUTE
          AND duration_ms IS NOT NULL
    """

    try:
        current_rows = ch.query(current_sql)
        baseline_rows = ch.query(baseline_sql)
    except Exception as exc:  # noqa: BLE001
        logger.error("Latency query failed for %s: %s", service, exc)
        return None

    current_p95 = current_rows[0]["p95"] if current_rows else None
    baseline_p95 = baseline_rows[0]["p95"] if baseline_rows else None

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
    ch,
    table,
    service: str,
    account_id: str,
    thresholds: dict[str, Any],
) -> dict[str, Any] | None:
    """Check if request volume has dropped by more than the threshold."""
    window = thresholds["traffic_drop_window_minutes"]
    drop_threshold = thresholds["traffic_drop_threshold"]
    cooldown = thresholds["cooldown_seconds"]

    sql = f"""
        SELECT
            countIf(timestamp >= now() - INTERVAL {window} MINUTE) AS recent_count,
            countIf(
                timestamp >= now() - INTERVAL {window * 2} MINUTE
                AND timestamp < now() - INTERVAL {window} MINUTE
            ) AS previous_count
        FROM aiops.logs
        WHERE service = '{service}'
          AND timestamp >= now() - INTERVAL {window * 2} MINUTE
    """

    try:
        rows = ch.query(sql)
        recent_count = int(rows[0]["recent_count"]) if rows else 0
        previous_count = int(rows[0]["previous_count"]) if rows else 0
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
    ch,
    table,
    account_id: str,
    thresholds: dict[str, Any],
) -> list[dict[str, Any]]:
    """Detect IAM policy changes from CloudTrail events in ClickHouse."""
    cooldown = thresholds["cooldown_seconds"]
    anomalies = []

    sql = """
        SELECT message, timestamp, account_id
        FROM aiops.logs
        WHERE service = 'cloudtrail'
          AND message IN (
              'CreatePolicy', 'DeletePolicy', 'AttachRolePolicy',
              'DetachRolePolicy', 'PutRolePolicy', 'DeleteRolePolicy'
          )
          AND timestamp >= now() - INTERVAL 15 MINUTE
        LIMIT 10
    """

    try:
        hits = ch.query(sql)
    except Exception as exc:  # noqa: BLE001
        logger.error("IAM change query failed for account %s: %s", account_id, exc)
        return []

    for hit in hits:
        event_name = hit.get("message", "IAMChange")

        if _is_in_cooldown(table, f"iam_change:{event_name}", "iam", cooldown):
            continue

        anomaly = _write_anomaly(
            table=table,
            rule_type="iam_policy_change",
            service="iam",
            account_id=account_id,
            description=f"IAM policy change detected: {event_name}",
            severity="medium",
            details={"event_name": event_name, "source_event": hit},
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

    ch = _get_clickhouse()
    table = _anomalies_table()

    detected: list[dict[str, Any]] = []

    for service in services:
        thresholds = _load_thresholds(service)

        anomaly = _check_error_rate(ch, table, service, account_id, thresholds)
        if anomaly:
            _insert_anomaly_to_clickhouse(ch, anomaly)
            detected.append(anomaly)

        anomaly = _check_latency_regression(ch, table, service, account_id, thresholds)
        if anomaly:
            _insert_anomaly_to_clickhouse(ch, anomaly)
            detected.append(anomaly)

        anomaly = _check_traffic_drop(ch, table, service, account_id, thresholds)
        if anomaly:
            _insert_anomaly_to_clickhouse(ch, anomaly)
            detected.append(anomaly)

    iam_anomalies = _check_iam_policy_changes(
        ch, table, account_id, _load_thresholds("iam")
    )
    for iam_anomaly in iam_anomalies:
        _insert_anomaly_to_clickhouse(ch, iam_anomaly)
    detected.extend(iam_anomalies)

    logger.info(
        "Rule detection complete: services=%d anomalies=%d",
        len(services), len(detected),
    )

    return {
        "anomalies_detected": len(detected),
        "anomaly_ids": [a["anomaly_id"] for a in detected],
    }
