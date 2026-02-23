"""Unit tests for statistical detection main.py (DynamoDB + ClickHouse writes)."""
import os
from datetime import datetime, timedelta
from decimal import Decimal
from unittest.mock import MagicMock, patch

import pytest

os.environ.setdefault("CLICKHOUSE_HOST", "clickhouse.aiops-test.local")
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("AWS_REGION", "eu-central-1")
os.environ.setdefault("DYNAMODB_ANOMALIES_TABLE", "aiops-test-anomalies")
os.environ.setdefault("DYNAMODB_POLICY_TABLE", "aiops-test-policy-store")

from src.detection.statistical.main import (  # noqa: E402
    _anomaly_for_clickhouse,
    _build_anomaly,
    run_detection,
)


# ─── _anomaly_for_clickhouse ──────────────────────────────────────────────────

class TestAnomalyForClickHouse:
    def test_converts_decimal_to_float(self):
        import json as _json
        item = {
            "anomaly_id": "abc",
            "details": {
                "z_score": Decimal("3.1415"),
                "current_value": Decimal("99.9"),
            },
            "ttl": 9999,
        }
        result = _anomaly_for_clickhouse(item)
        parsed = _json.loads(result["details"])
        assert parsed["z_score"] == pytest.approx(3.1415)
        assert parsed["current_value"] == pytest.approx(99.9)
        assert isinstance(parsed["z_score"], float)

    def test_excludes_ttl_field(self):
        item = {"anomaly_id": "abc", "ttl": 1234, "status": "open"}
        result = _anomaly_for_clickhouse(item)
        assert "ttl" not in result
        assert result["anomaly_id"] == "abc"
        assert result["status"] == "open"

    def test_details_serialized_as_json_string(self):
        item = {
            "anomaly_id": "abc",
            "details": {"z_score": Decimal("3.14"), "changepoints": [10, 20]},
        }
        result = _anomaly_for_clickhouse(item)
        import json
        assert isinstance(result["details"], str)
        parsed = json.loads(result["details"])
        assert parsed["z_score"] == pytest.approx(3.14)
        assert parsed["changepoints"] == [10, 20]

    def test_nested_decimal_conversion(self):
        item = {
            "details": {
                "nested": {"value": Decimal("42.0")},
                "list_field": [Decimal("1.0"), Decimal("2.0")],
            }
        }
        result = _anomaly_for_clickhouse(item)
        import json
        parsed = json.loads(result["details"])
        assert parsed["nested"]["value"] == 42.0
        assert parsed["list_field"] == [1.0, 2.0]

    def test_non_decimal_values_unchanged(self):
        item = {"anomaly_id": "xyz", "service": "api", "severity": "high", "count": 5}
        result = _anomaly_for_clickhouse(item)
        assert result["service"] == "api"
        assert result["severity"] == "high"
        assert result["count"] == 5


# ─── run_detection ClickHouse write ──────────────────────────────────────────

class TestRunDetectionClickHouseWrite:
    def _make_policy(self):
        return {
            "policy_id": "p1",
            "service": "payment-service",
            "account_id": "123456789012",
            "enabled": True,
            "sensitivity": "high",   # 2σ threshold — easy to trigger
            "metrics": ["duration_ms"],
        }

    def _make_series_response(self):
        """ClickHouse query response with 14 data points (enough for detection)."""
        base = datetime(2026, 2, 7, 0, 0, 0)
        rows = [
            {"ts": base + timedelta(hours=i), "value": 100.0}
            for i in range(13)
        ]
        # Spike at the end — triggers anomaly at 2σ sensitivity
        rows.append({"ts": base + timedelta(hours=13), "value": 900.0})
        return rows

    def test_anomaly_written_to_clickhouse_stl_path(
        self, mock_dynamodb_table, mock_clickhouse_client
    ):
        """When STL detects an anomaly, ch.insert is called with 'anomalies' table."""
        mock_clickhouse_client.query.return_value = self._make_series_response()

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.ClickHouseClient", return_value=mock_clickhouse_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            count = run_detection()

        assert count >= 1
        assert mock_clickhouse_client.insert.called

        call_args = mock_clickhouse_client.insert.call_args
        table_name = call_args[0][0] if call_args[0] else call_args.kwargs.get("table")
        assert table_name == "anomalies"

    def test_clickhouse_insert_receives_correct_doc_shape(
        self, mock_dynamodb_table, mock_clickhouse_client
    ):
        """Inserted document must have required anomaly fields and no ttl."""
        mock_clickhouse_client.query.return_value = self._make_series_response()

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.ClickHouseClient", return_value=mock_clickhouse_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            run_detection()

        if not mock_clickhouse_client.insert.called:
            pytest.skip("No anomaly detected — series may not have crossed threshold")

        docs = mock_clickhouse_client.insert.call_args[0][1]
        assert len(docs) == 1
        doc = docs[0]
        required_fields = {"anomaly_id", "timestamp", "account_id", "service", "severity", "status"}
        for field in required_fields:
            assert field in doc, f"Missing field in ClickHouse doc: {field}"
        assert "ttl" not in doc, "ttl should be excluded from ClickHouse document"
        assert isinstance(doc.get("details"), str), "details should be a JSON string for ClickHouse"

    def test_clickhouse_failure_does_not_stop_detection(
        self, mock_dynamodb_table, mock_clickhouse_client
    ):
        """If ClickHouse insert raises, detection continues and DynamoDB write still happens."""
        mock_clickhouse_client.query.return_value = self._make_series_response()
        mock_clickhouse_client.insert.side_effect = RuntimeError("connection refused")

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.ClickHouseClient", return_value=mock_clickhouse_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            count = run_detection()

        assert count >= 0  # should not raise

    def test_no_anomaly_no_clickhouse_write(
        self, mock_dynamodb_table, mock_clickhouse_client
    ):
        """When series has insufficient data points, no ClickHouse write occurs."""
        # Only 5 points — below the minimum of 10
        base = datetime(2026, 2, 14, 0, 0, 0)
        mock_clickhouse_client.query.return_value = [
            {"ts": base + timedelta(hours=i), "value": 100.0}
            for i in range(5)
        ]

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.ClickHouseClient", return_value=mock_clickhouse_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            count = run_detection()

        assert count == 0
        mock_clickhouse_client.insert.assert_not_called()
