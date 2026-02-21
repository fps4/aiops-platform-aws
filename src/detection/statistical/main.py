"""Fargate task entry point for statistical anomaly detection.

Runs every 5 minutes via EventBridge Scheduler. For each active detection
policy it queries a 7-day metric window from OpenSearch, applies STL + Z-score
+ PELT algorithms, and writes anomalies to DynamoDB.
"""
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import boto3
import pandas as pd

from src.detection.statistical import algorithms
from src.shared.logger import get_logger
from src.shared.opensearch_client import OpenSearchClient

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
    opensearch: OpenSearchClient,
    service: str,
    metric_field: str,
    window_days: int = 7,
    interval: str = "5m",
) -> pd.Series:
    """Fetch a time-bucketed metric series from OpenSearch.

    Args:
        opensearch: Initialised OpenSearch client.
        service: Service name to filter on.
        metric_field: Numeric field to aggregate (e.g. ``duration_ms``).
        window_days: Look-back window in days.
        interval: Date histogram interval.

    Returns:
        Pandas Series indexed by UTC timestamp, values are bucket averages.
    """
    query = {
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"service": service}},
                    {"range": {"timestamp": {"gte": f"now-{window_days}d"}}},
                ]
            }
        },
        "aggs": {
            "over_time": {
                "date_histogram": {
                    "field": "timestamp",
                    "fixed_interval": interval,
                    "min_doc_count": 1,
                },
                "aggs": {
                    "metric_value": {"avg": {"field": metric_field}}
                },
            }
        },
    }

    try:
        resp = opensearch.search(index=f"logs-{service}-*", body=query)
    except Exception as exc:  # noqa: BLE001
        logger.error(
            "Metric fetch failed",
            extra={"service": service, "metric": metric_field, "error": str(exc)},
        )
        return pd.Series(dtype=float)

    buckets = resp.get("aggregations", {}).get("over_time", {}).get("buckets", [])
    if not buckets:
        return pd.Series(dtype=float)

    timestamps = [b["key_as_string"] for b in buckets]
    values = [b.get("metric_value", {}).get("value") or 0.0 for b in buckets]

    index = pd.to_datetime(timestamps, utc=True)
    return pd.Series(values, index=index, dtype=float)


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


def _anomaly_for_opensearch(item: dict[str, Any]) -> dict[str, Any]:
    """Convert a DynamoDB anomaly item to an OpenSearch-safe document.

    Converts Decimal values to float (OpenSearch rejects DynamoDB Decimal types)
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

    exclude = {"ttl"}
    return {k: _convert(v) for k, v in item.items() if k not in exclude}


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
    opensearch = OpenSearchClient()
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

            series = _fetch_metric_series(opensearch, service, metric_field)
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
                    date = anomaly["timestamp"][:10].replace("-", ".")
                    try:
                        opensearch.index(
                            index=f"anomalies-{date}",
                            doc=_anomaly_for_opensearch(anomaly),
                            doc_id=anomaly["anomaly_id"],
                        )
                    except Exception as exc:  # noqa: BLE001
                        logger.warning(
                            "Failed to index anomaly to OpenSearch",
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
                date = anomaly["timestamp"][:10].replace("-", ".")
                try:
                    opensearch.index(
                        index=f"anomalies-{date}",
                        doc=_anomaly_for_opensearch(anomaly),
                        doc_id=anomaly["anomaly_id"],
                    )
                except Exception as exc:  # noqa: BLE001
                    logger.warning(
                        "Failed to index anomaly to OpenSearch",
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
