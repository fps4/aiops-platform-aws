"""Unit tests for the log-normalizer Firehose Lambda.

The handler lives in ``src/ingestion/lambda/log-normalizer/handler.py``.
Because "lambda" is a Python keyword and "log-normalizer" contains a hyphen,
we load the module via importlib rather than a standard import statement.
"""
import base64
import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import pytest

# ── env vars ──────────────────────────────────────────────────────────────────
os.environ.setdefault("OPENSEARCH_ENDPOINT", "https://example.es.amazonaws.com")
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("RAW_LOGS_BUCKET", "test-raw-logs")
os.environ.setdefault("AWS_REGION", "eu-central-1")

# ── load handler module by file path ─────────────────────────────────────────
_HANDLER_PATH = (
    Path(__file__).parent.parent.parent
    / "src" / "ingestion" / "lambda" / "log-normalizer" / "handler.py"
)

_MODULE_NAME = "log_normalizer_handler"

# Load once and register in sys.modules so module-level state is shared
_spec = importlib.util.spec_from_file_location(_MODULE_NAME, _HANDLER_PATH)
_handler_module = importlib.util.module_from_spec(_spec)
sys.modules[_MODULE_NAME] = _handler_module
_spec.loader.exec_module(_handler_module)


# ── helpers ───────────────────────────────────────────────────────────────────

def _encode(data: dict[str, Any]) -> str:
    return base64.b64encode(json.dumps(data).encode()).decode()


def _decode_result_data(result: dict[str, Any]) -> dict[str, Any]:
    raw = base64.b64decode(result["data"]).decode().strip()
    return json.loads(raw)


# ── fixture: inject mock OpenSearch into handler singleton ────────────────────

@pytest.fixture(autouse=True)
def inject_mock_opensearch(mock_opensearch_client):
    """Inject mock directly into the handler's module-level singleton."""
    _handler_module._opensearch = mock_opensearch_client
    yield
    _handler_module._opensearch = None  # reset after each test


# ─────────────────────────────────────────────────────────────────────────────

class TestCanonicalSchemaFieldsPresent:
    def test_all_canonical_fields_present(self, sample_cloudwatch_log_event):
        response = _handler_module.lambda_handler(sample_cloudwatch_log_event, None)
        for result in response["records"]:
            if result["result"] == "Ok":
                doc = _decode_result_data(result)
                for field in _handler_module.CANONICAL_FIELDS:
                    assert field in doc, f"Missing canonical field: {field}"

    def test_extra_fields_stored_under_raw(self, sample_cloudwatch_log_event):
        """Fields not in canonical schema are preserved under _raw."""
        response = _handler_module.lambda_handler(sample_cloudwatch_log_event, None)
        ok_results = [r for r in response["records"] if r["result"] == "Ok"]
        assert len(ok_results) > 0
        doc = _decode_result_data(ok_results[0])
        assert "_raw" in doc


class TestLogLevelExtraction:
    @pytest.mark.parametrize("raw_level,expected", [
        ("error", "ERROR"),
        ("ERROR", "ERROR"),
        ("warn", "WARN"),
        ("warning", "WARN"),
        ("info", "INFO"),
        ("INFO", "INFO"),
        ("debug", "DEBUG"),
        ("critical", "CRITICAL"),
        ("fatal", "CRITICAL"),
    ])
    def test_log_level_from_level_field(self, raw_level, expected):
        record = {"service": "svc", "message": "test", "level": raw_level}
        result = _handler_module._extract_log_level(record)
        assert result == expected

    def test_log_level_inferred_from_message(self):
        record = {"service": "svc", "message": "ERROR: something went wrong"}
        assert _handler_module._extract_log_level(record) == "ERROR"

    def test_log_level_defaults_to_info(self):
        record = {"service": "svc", "message": "hello world"}
        assert _handler_module._extract_log_level(record) == "INFO"

    def test_log_level_field_priority_over_message(self):
        """Explicit level field takes priority over inferred from message text."""
        record = {"level": "debug", "message": "ERROR in message text"}
        assert _handler_module._extract_log_level(record) == "DEBUG"


class TestMissingFieldsUseDefaults:
    def test_minimal_record_normalizes_without_error(self):
        minimal = {"message": "hello"}
        result = _handler_module._normalize_record(minimal)
        assert result["account_id"] == "unknown"
        assert result["service"] == "unknown"
        assert result["log_level"] == "INFO"
        assert result["deployment_version"] == "unknown"
        assert result["related_events"] == []

    def test_service_extracted_from_log_group(self):
        record = {"message": "hi", "logGroup": "/aws/lambda/my-service"}
        result = _handler_module._normalize_record(record)
        assert result["service"] == "my-service"

    def test_timestamp_defaults_to_now(self):
        record = {"message": "no timestamp"}
        result = _handler_module._normalize_record(record)
        assert result["timestamp"]  # non-empty


class TestFirehoseRecordBase64Decode:
    def test_standard_base64_decoded_correctly(self):
        data = {"service": "api", "message": "ok", "log_level": "INFO"}
        encoded = base64.b64encode(json.dumps(data).encode()).decode()
        record = {"recordId": "r1", "data": encoded}
        result = _handler_module._process_record(record)
        assert result["result"] == "Ok"
        doc = _decode_result_data(result)
        assert doc["service"] == "api"

    def test_empty_data_is_dropped(self):
        empty_encoded = base64.b64encode(b"  ").decode()
        record = {"recordId": "r1", "data": empty_encoded}
        result = _handler_module._process_record(record)
        assert result["result"] == "Dropped"


class TestFirehoseResponseFormat:
    def test_response_has_records_key(self, sample_cloudwatch_log_event):
        response = _handler_module.lambda_handler(sample_cloudwatch_log_event, None)
        assert "records" in response

    def test_record_count_matches_input(self, sample_cloudwatch_log_event):
        response = _handler_module.lambda_handler(sample_cloudwatch_log_event, None)
        assert len(response["records"]) == len(sample_cloudwatch_log_event["records"])

    def test_each_result_has_required_fields(self, sample_cloudwatch_log_event):
        response = _handler_module.lambda_handler(sample_cloudwatch_log_event, None)
        for result in response["records"]:
            assert "recordId" in result
            assert "result" in result
            assert "data" in result
            assert result["result"] in ("Ok", "Dropped", "ProcessingFailed")

    def test_record_ids_preserved(self, sample_cloudwatch_log_event):
        input_ids = [r["recordId"] for r in sample_cloudwatch_log_event["records"]]
        response = _handler_module.lambda_handler(sample_cloudwatch_log_event, None)
        output_ids = [r["recordId"] for r in response["records"]]
        assert input_ids == output_ids


class TestMalformedRecordMarkedProcessingFailed:
    def test_invalid_json_returns_processing_failed(self, malformed_firehose_event):
        response = _handler_module.lambda_handler(malformed_firehose_event, None)
        results_by_id = {r["recordId"]: r for r in response["records"]}
        assert results_by_id["good-record"]["result"] == "Ok"
        assert results_by_id["bad-record"]["result"] == "ProcessingFailed"

    def test_malformed_record_does_not_crash_batch(self, malformed_firehose_event):
        """The entire batch should still return even when one record is bad."""
        response = _handler_module.lambda_handler(malformed_firehose_event, None)
        assert len(response["records"]) == 2

    def test_processing_failed_preserves_original_data(self, malformed_firehose_event):
        """ProcessingFailed records must return the original (unchanged) data."""
        original_data = {
            r["recordId"]: r["data"] for r in malformed_firehose_event["records"]
        }
        response = _handler_module.lambda_handler(malformed_firehose_event, None)
        for result in response["records"]:
            if result["result"] == "ProcessingFailed":
                assert result["data"] == original_data[result["recordId"]]
