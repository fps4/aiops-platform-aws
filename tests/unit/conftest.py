"""Shared pytest fixtures for unit tests."""
import base64
import json
import sys
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import numpy as np
import pytest

# Ensure project root is on sys.path so `from src.xxx import` works
_PROJECT_ROOT = Path(__file__).parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))


# ─── Firehose payloads ────────────────────────────────────────────────────────

def _encode_record(data: dict[str, Any]) -> str:
    return base64.b64encode(json.dumps(data).encode()).decode()


@pytest.fixture
def sample_cloudwatch_log_event() -> dict[str, Any]:
    """Realistic Firehose invocation event with two log records."""
    records = [
        {
            "timestamp": "2026-02-21T12:00:00Z",
            "account_id": "123456789012",
            "region": "eu-central-1",
            "service": "payment-service",
            "log_level": "ERROR",
            "message": "Payment processing failed: timeout",
            "appVersion": "2.1.0",
        },
        {
            "timestamp": "2026-02-21T12:00:05Z",
            "accountId": "123456789012",
            "awsRegion": "eu-central-1",
            "logGroup": "/aws/lambda/checkout-service",
            "level": "INFO",
            "msg": "Order created successfully",
        },
    ]
    return {
        "records": [
            {"recordId": f"record-{i}", "data": _encode_record(r)}
            for i, r in enumerate(records)
        ]
    }


@pytest.fixture
def malformed_firehose_event() -> dict[str, Any]:
    """Firehose event with one good record and one with invalid JSON."""
    good = {"service": "api", "message": "ok", "log_level": "INFO"}
    bad_bytes = base64.b64encode(b"not-json-{{{").decode()
    return {
        "records": [
            {"recordId": "good-record", "data": _encode_record(good)},
            {"recordId": "bad-record", "data": bad_bytes},
        ]
    }


# ─── Time series ──────────────────────────────────────────────────────────────

@pytest.fixture
def sample_metrics_series() -> np.ndarray:
    """7-day 5-minute resolution time series with a spike at the last point.

    The baseline is ~100 with Gaussian noise (std=5). The final point is 200
    (i.e. ~20σ above the mean), making it clearly anomalous.
    """
    rng = np.random.default_rng(42)
    n_points = 7 * 24 * 12  # 7 days × 5-min intervals
    baseline = rng.normal(loc=100.0, scale=5.0, size=n_points - 1)
    spike = np.array([200.0])
    return np.concatenate([baseline, spike])


@pytest.fixture
def normal_metrics_series() -> np.ndarray:
    """7-day series with only normal variation (no anomaly)."""
    rng = np.random.default_rng(7)
    n_points = 7 * 24 * 12
    return rng.normal(loc=100.0, scale=5.0, size=n_points)


# ─── Policies ─────────────────────────────────────────────────────────────────

@pytest.fixture
def sample_policy() -> dict[str, Any]:
    """Default detection policy dict matching the DynamoDB policy_store schema."""
    return {
        "policy_id": "policy-001",
        "service": "payment-service",
        "account_id": "123456789012",
        "enabled": True,
        "sensitivity": "medium",
        "metrics": ["duration_ms", "error_count"],
        "detection": {
            "type": "statistical",
            "window_days": 7,
        },
        "actions": {
            "alert": True,
            "run_rca": True,
        },
    }


# ─── Mock clients ─────────────────────────────────────────────────────────────

@pytest.fixture
def mock_opensearch_client() -> MagicMock:
    """Mock OpenSearchClient with canned aggregation responses."""
    client = MagicMock()

    # Default search response: 1000 total, 60 errors → 6% error rate
    client.search.return_value = {
        "hits": {"total": {"value": 1000}},
        "aggregations": {
            "total": {"value": 1000},
            "errors": {"count": {"value": 60}},
            "p95_latency": {"values": {"95.0": 500.0}},
            "recent": {"count": {"value": 100}},
            "previous": {"count": {"value": 1000}},
            "over_time": {
                "buckets": [
                    {
                        "key_as_string": f"2026-02-{14 + i:02d}T00:00:00Z",
                        "metric_value": {"value": 100.0 + i},
                    }
                    for i in range(7)
                ]
            },
        },
    }
    client.index.return_value = {"result": "created"}
    client.bulk_index.return_value = {"errors": False, "items": []}
    return client


@pytest.fixture
def mock_dynamodb_table() -> MagicMock:
    """Simple mock DynamoDB table backed by an in-memory dict."""
    store: dict[str, Any] = {}

    table = MagicMock()

    def put_item(Item: dict[str, Any], **kwargs):
        key = (
            Item.get("anomaly_id")
            or Item.get("policy_id")
            or str(len(store))
        )
        store[key] = Item
        return {}

    def get_item(Key: dict[str, Any], **kwargs):
        pk_val = next(iter(Key.values()), None)
        item = store.get(str(pk_val))
        return {"Item": item} if item else {}

    def query(**kwargs):
        return {"Items": list(store.values())}

    def scan(**kwargs):
        return {"Items": list(store.values())}

    table.put_item.side_effect = put_item
    table.get_item.side_effect = get_item
    table.query.side_effect = query
    table.scan.side_effect = scan

    table._store = store
    return table
