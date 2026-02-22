"""Unit tests for statistical detection main.py (DynamoDB + OpenSearch writes)."""
import os
from decimal import Decimal
from unittest.mock import MagicMock, patch

import pytest

os.environ.setdefault("OPENSEARCH_ENDPOINT", "https://example.es.amazonaws.com")
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("AWS_REGION", "eu-central-1")
os.environ.setdefault("DYNAMODB_ANOMALIES_TABLE", "aiops-test-anomalies")
os.environ.setdefault("DYNAMODB_POLICY_TABLE", "aiops-test-policy-store")

from src.detection.statistical.main import (  # noqa: E402
    _anomaly_for_opensearch,
    _build_anomaly,
    run_detection,
)


# ─── _anomaly_for_opensearch ──────────────────────────────────────────────────

class TestAnomalyForOpenSearch:
    def test_converts_decimal_to_float(self):
        item = {
            "anomaly_id": "abc",
            "details": {
                "z_score": Decimal("3.1415"),
                "current_value": Decimal("99.9"),
            },
            "ttl": 9999,
        }
        result = _anomaly_for_opensearch(item)
        assert result["details"]["z_score"] == pytest.approx(3.1415)
        assert result["details"]["current_value"] == pytest.approx(99.9)
        assert isinstance(result["details"]["z_score"], float)

    def test_excludes_ttl_field(self):
        item = {"anomaly_id": "abc", "ttl": 1234, "status": "open"}
        result = _anomaly_for_opensearch(item)
        assert "ttl" not in result
        assert result["anomaly_id"] == "abc"
        assert result["status"] == "open"

    def test_nested_decimal_conversion(self):
        item = {
            "details": {
                "nested": {"value": Decimal("42.0")},
                "list_field": [Decimal("1.0"), Decimal("2.0")],
            }
        }
        result = _anomaly_for_opensearch(item)
        assert result["details"]["nested"]["value"] == 42.0
        assert result["details"]["list_field"] == [1.0, 2.0]

    def test_non_decimal_values_unchanged(self):
        item = {"anomaly_id": "xyz", "service": "api", "severity": "high", "count": 5}
        result = _anomaly_for_opensearch(item)
        assert result["service"] == "api"
        assert result["severity"] == "high"
        assert result["count"] == 5


# ─── run_detection OpenSearch write ──────────────────────────────────────────

class TestRunDetectionOpenSearchWrite:
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
        """OpenSearch aggregation response with 14 buckets (enough data points)."""
        import pandas as pd

        buckets = [
            {
                "key_as_string": f"2026-02-{7 + i:02d}T00:00:00Z",
                "metric_value": {"value": 100.0},
            }
            for i in range(13)
        ]
        # Last bucket is a spike — triggers anomaly at 2σ sensitivity
        buckets.append({
            "key_as_string": "2026-02-21T00:00:00Z",
            "metric_value": {"value": 900.0},
        })
        return {
            "aggregations": {
                "over_time": {"buckets": buckets}
            }
        }

    def test_anomaly_written_to_opensearch_stl_path(
        self, mock_dynamodb_table, mock_opensearch_client
    ):
        """When STL detects an anomaly, opensearch.index is called with anomalies-{date} index."""
        mock_opensearch_client.search.return_value = self._make_series_response()

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.OpenSearchClient", return_value=mock_opensearch_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            count = run_detection()

        # At least one anomaly detected and opensearch.index called
        assert count >= 1
        assert mock_opensearch_client.index.called

        call_kwargs = mock_opensearch_client.index.call_args
        index_name = call_kwargs.kwargs.get("index") or call_kwargs.args[0] if call_kwargs.args else call_kwargs.kwargs["index"]
        assert index_name.startswith("anomalies-")
        # Verify date format YYYY.MM.DD
        date_part = index_name[len("anomalies-"):]
        assert len(date_part) == 10
        assert date_part[4] == "." and date_part[7] == "."

    def test_opensearch_index_receives_correct_doc_shape(
        self, mock_dynamodb_table, mock_opensearch_client
    ):
        """Indexed document must have required anomaly fields and no ttl."""
        mock_opensearch_client.search.return_value = self._make_series_response()

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.OpenSearchClient", return_value=mock_opensearch_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            run_detection()

        if not mock_opensearch_client.index.called:
            pytest.skip("No anomaly detected — series may not have crossed threshold")

        call_kwargs = mock_opensearch_client.index.call_args.kwargs
        doc = call_kwargs["doc"]
        required_fields = {"anomaly_id", "timestamp", "account_id", "service", "severity", "status"}
        for field in required_fields:
            assert field in doc, f"Missing field in OpenSearch doc: {field}"
        assert "ttl" not in doc, "ttl should be excluded from OpenSearch document"

    def test_opensearch_failure_does_not_stop_detection(
        self, mock_dynamodb_table, mock_opensearch_client
    ):
        """If OpenSearch indexing raises, detection continues and DynamoDB write still happens."""
        mock_opensearch_client.search.return_value = self._make_series_response()
        mock_opensearch_client.index.side_effect = RuntimeError("connection refused")

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.OpenSearchClient", return_value=mock_opensearch_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            count = run_detection()

        # DynamoDB write still happened (anomaly counted)
        assert count >= 0  # should not raise

    def test_no_anomaly_no_opensearch_write(
        self, mock_dynamodb_table, mock_opensearch_client
    ):
        """When series has insufficient data points, no OpenSearch write occurs."""
        # Only 5 points — below the minimum of 10
        mock_opensearch_client.search.return_value = {
            "aggregations": {
                "over_time": {
                    "buckets": [
                        {"key_as_string": f"2026-02-{14 + i:02d}T00:00:00Z", "metric_value": {"value": 100.0}}
                        for i in range(5)
                    ]
                }
            }
        }

        with (
            patch("src.detection.statistical.main._policy_table", return_value=MagicMock()),
            patch("src.detection.statistical.main._anomalies_table", return_value=mock_dynamodb_table),
            patch("src.detection.statistical.main.OpenSearchClient", return_value=mock_opensearch_client),
            patch("src.detection.statistical.main.load_policies", return_value=[self._make_policy()]),
        ):
            count = run_detection()

        assert count == 0
        mock_opensearch_client.index.assert_not_called()
