"""Fargate task entry point for statistical anomaly detection.

Runs every 5 minutes via EventBridge Scheduler. For each active detection
policy it queries a 7-day metric window from ClickHouse, applies STL + Z-score
+ PELT algorithms, and writes anomalies to DynamoDB.
"""
import json
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import boto3
import pandas as pd

from src.detection.statistical import algorithms
from src.shared.logger import get_logger
from src.shared.clickhouse_client import ClickHouseClient

logger = get_logger("statistical-detection")

_region = os.environ.get("AWS_REGION", "eu-central-1")
_dynamodb = boto3.resource("dynamodb", region_name=_region)


def _policy_table():
    return _dynamodb.Table(os.environ["DYNAMODB_POLICY_TABLE"])


def _anomalies_table():
    return _dynamodb.Table(os.environ["DYNAMODB_ANOMALIES_TABLE"])


# ─── Policy loading ───────────────────────────────────────────────────────────

def load_policies(table) -> list[dict[str, Any]]:
    """Load all active detection policies from DynamoDB."""
    try:
        resp = table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr("enabled").eq(True)
        )
        policies = resp.get("Items", [])
        logger.info("Loaded policies", extra={"count": len(policies)})
        return policies
    except Exception as exc:  # noqa: BLE001
        logger.error("Failed to load policies", extra={"error": str(exc)})
        return []


# ─── Metric retrieval ─────────────────────────────────────────────────────────

def _fetch_metric_series(
    ch: ClickHouseClient,
    service: str,
    metric_field: str,
    window_days: int = 7,
) -> pd.Series:
    """Fetch a 5-minute-bucketed metric series from ClickHouse.

    Args:
        ch:           Initialised ClickHouse client.
        service:      Service name to filter on.
        metric_field: Numeric column to aggregate (e.g. ``duration_ms``).
        window_days:  Look-back window in days.

    Returns:
        Pandas Series indexed by UTC timestamp, values are bucket averages.
    """
    sql = f"""
        SELECT
            toStartOfInterval(timestamp, INTERVAL 5 MINUTE) AS ts,
            avg({metric_field}) AS value
        FROM aiops.logs
        WHERE service = '{service}'
          AND timestamp >= now() - INTERVAL {window_days} DAY
          AND {metric_field} IS NOT NULL
        GROUP BY ts
        ORDER BY ts
    """

    try:
        rows = ch.query(sql)
    except Exception as exc:  # noqa: BLE001
        logger.error(
            "Metric fetch failed",
            extra={"service": service, "metric": metric_field, "error": str(exc)},
        )
        return pd.Series(dtype=float)

    if not rows:
        return pd.Series(dtype=float)

    timestamps = pd.to_datetime([r["ts"] for r in rows], utc=True)
    values = [float(r["value"] or 0.0) for r in rows]

    return pd.Series(values, index=timestamps, dtype=float)


# ─── Anomaly construction ─────────────────────────────────────────────────────

def _build_anomaly(
    policy: dict[str, Any],
    service: str,
    metric_field: str,
    z: float,
    changepoints: list[int],
    current_value: float,
) -> dict[str, Any]:
    """Build a DynamoDB anomaly item."""
    now = datetime.now(timezone.utc)
    return {
        "anomaly_id": str(uuid.uuid4()),
        "timestamp": now.isoformat(),
        "account_id": policy.get("account_id", "unknown"),
        "service": service,
        "rule_type": "statistical",
        "detection_method": "statistical",
        "severity": _severity_from_z(z),
        "description": (
            f"Statistical anomaly on {metric_field} for {service}: "
            f"Z-score {z:.2f} (sensitivity={policy.get('sensitivity', 'medium')})"
        ),
        "details": {
            "metric_field": metric_field,
            "z_score": Decimal(str(round(z, 4))),
            "current_value": Decimal(str(round(current_value, 4))),
            "changepoints": changepoints,
            "policy_id": policy.get("policy_id", ""),
            "sensitivity": policy.get("sensitivity", "medium"),
        },
        "status": "open",
        "environment": os.environ.get("ENVIRONMENT", "unknown"),
        "ttl": int(now.timestamp()) + 7 * 24 * 3600,
    }


def _anomaly_for_clickhouse(item: dict[str, Any]) -> dict[str, Any]:
    """Convert a DynamoDB anomaly item to a ClickHouse-safe document.

    Converts Decimal values to float, serialises the details dict to JSON,
    and drops DynamoDB-specific fields like ttl.
    """
    def _convert(v: Any) -> Any:
        from decimal import Decimal as _Decimal
        if isinstance(v, _Decimal):
            return float(v)
        if isinstance(v, dict):
            return {k: _convert(val) for k, val in v.items()}
        if isinstance(v, list):
            return [_convert(i) for i in v]
        return v

    exclude = {"ttl", "details"}
    doc = {k: _convert(v) for k, v in item.items() if k not in exclude}
    doc["details"] = json.dumps(_convert(item.get("details", {})))
    return doc


def _severity_from_z(z: float) -> str:
    az = abs(z)
    if az >= 4:
        return "critical"
    if az >= 3:
        return "high"
    return "medium"


# ─── Core detection loop ──────────────────────────────────────────────────────

def run_detection() -> int:
    """Run statistical detection for all active policies.

    Returns:
        Total number of anomalies written.
    """
    ch = ClickHouseClient()
    policies = load_policies(_policy_table())
    anomalies_table = _anomalies_table()
    total_anomalies = 0

    for policy in policies:
        service = policy.get("service", "unknown")
        sensitivity = policy.get("sensitivity", "medium")
        metrics: list[str] = policy.get("metrics", [])

        for metric_field in metrics:
            logger.info(
                "Evaluating metric",
                extra={"service": service, "metric": metric_field, "sensitivity": sensitivity},
            )

            series = _fetch_metric_series(ch, service, metric_field)
            if len(series) < 10:
                logger.info(
                    "Insufficient data for statistical detection",
                    extra={"service": service, "metric": metric_field, "points": len(series)},
                )
                continue

            try:
                trend, seasonal, residual = algorithms.stl_decompose(series)
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "STL decomposition failed, falling back to EWMA",
                    extra={"service": service, "metric": metric_field, "error": str(exc)},
                )
                score = algorithms.ewma_score(series.values)
                current_value = float(series.iloc[-1])
                if algorithms.is_anomaly(score, sensitivity):
                    anomaly = _build_anomaly(policy, service, metric_field, score, [], current_value)
                    anomalies_table.put_item(Item=anomaly)
                    try:
                        ch.insert("anomalies", [_anomaly_for_clickhouse(anomaly)])
                    except Exception as exc:  # noqa: BLE001
                        logger.warning(
                            "Failed to insert anomaly to ClickHouse",
                            extra={"anomaly_id": anomaly["anomaly_id"], "error": str(exc)},
                        )
                    total_anomalies += 1
                continue

            current_residual = float(residual[-1])
            z = algorithms.z_score(current_residual, residual[:-1])

            # Changepoint detection on the trend component
            changepoints: list[int] = []
            try:
                changepoints = algorithms.pelt_changepoints(trend)
            except Exception as exc:  # noqa: BLE001
                logger.debug(
                    "Changepoint detection skipped",
                    extra={"service": service, "error": str(exc)},
                )

            if algorithms.is_anomaly(z, sensitivity):
                current_value = float(series.iloc[-1])
                anomaly = _build_anomaly(
                    policy, service, metric_field, z, changepoints, current_value
                )
                anomalies_table.put_item(Item=anomaly)
                try:
                    ch.insert("anomalies", [_anomaly_for_clickhouse(anomaly)])
                except Exception as exc:  # noqa: BLE001
                    logger.warning(
                        "Failed to insert anomaly to ClickHouse",
                        extra={"anomaly_id": anomaly["anomaly_id"], "error": str(exc)},
                    )
                total_anomalies += 1
                logger.info(
                    "Statistical anomaly detected",
                    extra={
                        "service": service,
                        "metric": metric_field,
                        "z_score": z,
                        "anomaly_id": anomaly["anomaly_id"],
                    },
                )

    logger.info("Detection run complete", extra={"total_anomalies": total_anomalies})
    return total_anomalies


if __name__ == "__main__":
    run_detection()
