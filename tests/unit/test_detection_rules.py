"""Unit tests for the rule-based detection Lambda."""
import os
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

os.environ.setdefault("OPENSEARCH_ENDPOINT", "https://example.es.amazonaws.com")
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("AWS_REGION", "eu-central-1")
os.environ.setdefault("DYNAMODB_ANOMALIES_TABLE", "aiops-test-anomalies")
os.environ.setdefault("DYNAMODB_POLICY_TABLE", "aiops-test-policy-store")

from src.detection.rules import handler  # noqa: E402


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_agg_response(total: int, errors: int, p95: float, recent: int, previous: int) -> dict:
    return {
        "hits": {"total": {"value": total}},
        "aggregations": {
            "total": {"value": total},
            "errors": {"count": {"value": errors}},
            "p95_latency": {"values": {"95.0": p95}},
            "recent": {"count": {"value": recent}},
            "previous": {"count": {"value": previous}},
        },
    }


def _default_thresholds() -> dict[str, Any]:
    return {
        "error_rate_threshold": 0.05,
        "error_rate_window_minutes": 5,
        "latency_multiplier": 2.0,
        "latency_window_minutes": 3,
        "traffic_drop_threshold": 0.80,
        "traffic_drop_window_minutes": 10,
        "cooldown_seconds": 300,
    }


@pytest.fixture(autouse=True)
def reset_opensearch_singleton():
    """Reset the module-level OpenSearch singleton between tests."""
    handler._opensearch = None
    yield
    handler._opensearch = None


# ─── Error rate ───────────────────────────────────────────────────────────────

class TestErrorRateThreshold:
    def test_error_rate_threshold_breach(self, mock_opensearch_client, mock_dynamodb_table):
        """6% error rate (above 5% threshold) should write an anomaly."""
        mock_opensearch_client.search.return_value = _make_agg_response(1000, 60, 200, 100, 100)
        result = handler._check_error_rate(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is not None
        assert result["rule_type"] == "error_rate"
        assert result["severity"] == "high"
        assert result["details"]["error_rate"] == pytest.approx(0.06)

    def test_error_rate_below_threshold(self, mock_opensearch_client, mock_dynamodb_table):
        """4% error rate (below 5% threshold) should not produce an anomaly."""
        mock_opensearch_client.search.return_value = _make_agg_response(1000, 40, 200, 100, 100)
        result = handler._check_error_rate(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is None

    def test_error_rate_zero_total_no_anomaly(self, mock_opensearch_client, mock_dynamodb_table):
        """Zero log volume should not produce an anomaly."""
        mock_opensearch_client.search.return_value = _make_agg_response(0, 0, 0, 0, 0)
        result = handler._check_error_rate(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is None


# ─── Latency regression ───────────────────────────────────────────────────────

class TestLatencyRegressionDetection:
    def test_latency_regression_detection(self, mock_opensearch_client, mock_dynamodb_table):
        """P95 > 2× baseline should trigger a latency anomaly."""
        mock_opensearch_client.search.side_effect = [
            {"aggregations": {"p95_latency": {"values": {"95.0": 500.0}}}},
            {"aggregations": {"p95_latency": {"values": {"95.0": 200.0}}}},
        ]
        result = handler._check_latency_regression(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is not None
        assert result["rule_type"] == "latency_regression"
        assert result["details"]["current_p95_ms"] == 500.0
        assert result["details"]["baseline_p95_ms"] == 200.0

    def test_latency_within_threshold_no_anomaly(self, mock_opensearch_client, mock_dynamodb_table):
        """P95 = 1.5× baseline (below 2×) should not trigger."""
        mock_opensearch_client.search.side_effect = [
            {"aggregations": {"p95_latency": {"values": {"95.0": 300.0}}}},
            {"aggregations": {"p95_latency": {"values": {"95.0": 200.0}}}},
        ]
        result = handler._check_latency_regression(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is None

    def test_latency_missing_baseline_no_anomaly(self, mock_opensearch_client, mock_dynamodb_table):
        """No baseline data (None value) should not trigger."""
        mock_opensearch_client.search.side_effect = [
            {"aggregations": {"p95_latency": {"values": {"95.0": 500.0}}}},
            {"aggregations": {"p95_latency": {"values": {"95.0": None}}}},
        ]
        result = handler._check_latency_regression(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is None


# ─── Traffic drop ─────────────────────────────────────────────────────────────

class TestTrafficDropDetection:
    def test_traffic_drop_detection(self, mock_opensearch_client, mock_dynamodb_table):
        """85% traffic drop should trigger a critical anomaly."""
        mock_opensearch_client.search.return_value = {
            "aggregations": {
                "recent": {"count": {"value": 15}},
                "previous": {"count": {"value": 100}},
            }
        }
        result = handler._check_traffic_drop(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is not None
        assert result["rule_type"] == "traffic_drop"
        assert result["severity"] == "critical"
        assert result["details"]["drop_ratio"] == pytest.approx(0.85)

    def test_traffic_drop_below_threshold(self, mock_opensearch_client, mock_dynamodb_table):
        """50% drop (below 80% threshold) should not trigger."""
        mock_opensearch_client.search.return_value = {
            "aggregations": {
                "recent": {"count": {"value": 50}},
                "previous": {"count": {"value": 100}},
            }
        }
        result = handler._check_traffic_drop(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is None

    def test_traffic_drop_zero_previous_no_anomaly(self, mock_opensearch_client, mock_dynamodb_table):
        """No historical traffic baseline → no anomaly."""
        mock_opensearch_client.search.return_value = {
            "aggregations": {
                "recent": {"count": {"value": 0}},
                "previous": {"count": {"value": 0}},
            }
        }
        result = handler._check_traffic_drop(
            mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
        )
        assert result is None


# ─── Anomaly object schema ────────────────────────────────────────────────────

class TestAnomalyObjectSchema:
    def test_anomaly_object_schema(self, mock_dynamodb_table):
        """Written anomaly item must contain all required DynamoDB schema fields."""
        anomaly = handler._write_anomaly(
            table=mock_dynamodb_table,
            rule_type="error_rate",
            service="checkout",
            account_id="123456789012",
            description="Test anomaly",
            severity="high",
            details={"error_rate": 0.06},
        )
        required_fields = {
            "anomaly_id", "timestamp", "account_id", "service",
            "rule_type", "severity", "description", "details",
            "status", "detection_method", "environment", "ttl",
        }
        for field in required_fields:
            assert field in anomaly, f"Missing field: {field}"

        assert anomaly["status"] == "open"
        assert anomaly["detection_method"] == "rule-based"
        assert isinstance(anomaly["ttl"], int)

    def test_anomaly_id_is_unique(self, mock_dynamodb_table):
        ids = set()
        for _ in range(10):
            anomaly = handler._write_anomaly(
                table=mock_dynamodb_table,
                rule_type="error_rate",
                service="svc",
                account_id="acct",
                description="desc",
                severity="high",
                details={},
            )
            ids.add(anomaly["anomaly_id"])
        assert len(ids) == 10

    def test_anomaly_persisted_to_table(self, mock_dynamodb_table):
        anomaly = handler._write_anomaly(
            table=mock_dynamodb_table,
            rule_type="traffic_drop",
            service="api",
            account_id="123",
            description="desc",
            severity="critical",
            details={"drop_ratio": 0.9},
        )
        assert anomaly["anomaly_id"] in mock_dynamodb_table._store


# ─── Cooldown suppression ─────────────────────────────────────────────────────

class TestCooldownSuppresssDuplicate:
    def test_cooldown_suppresses_duplicate(self, mock_opensearch_client, mock_dynamodb_table):
        """Second anomaly call within cooldown window should be suppressed."""
        mock_opensearch_client.search.return_value = _make_agg_response(1000, 60, 200, 100, 100)

        call_count = {"n": 0}

        def fake_cooldown(table, rule_type, service, cooldown_seconds):
            call_count["n"] += 1
            return call_count["n"] > 1  # first call: no cooldown; subsequent: in cooldown

        with patch.object(handler, "_is_in_cooldown", side_effect=fake_cooldown):
            first = handler._check_error_rate(
                mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
            )
            second = handler._check_error_rate(
                mock_opensearch_client, mock_dynamodb_table, "api", "123", _default_thresholds()
            )

        assert first is not None, "First detection should produce an anomaly"
        assert second is None, "Second detection within cooldown should be suppressed"

    def test_is_in_cooldown_false_when_no_recent_anomalies(self, mock_dynamodb_table):
        """Empty anomaly table → not in cooldown."""
        mock_dynamodb_table.query.side_effect = lambda **kwargs: {"Items": []}
        result = handler._is_in_cooldown(mock_dynamodb_table, "error_rate", "api", 300)
        assert result is False

    def test_is_in_cooldown_true_when_recent_anomaly_exists(self, mock_dynamodb_table):
        """Existing recent anomaly in table → in cooldown."""
        mock_dynamodb_table.query.side_effect = lambda **kwargs: {
            "Items": [{"anomaly_id": "existing", "service": "api", "rule_type": "error_rate"}]
        }
        result = handler._is_in_cooldown(mock_dynamodb_table, "error_rate", "api", 300)
        assert result is True
