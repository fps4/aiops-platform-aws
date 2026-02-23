"""Kinesis Firehose data transformation Lambda.

Decodes each Firehose record, normalizes it to the canonical log schema,
inserts the normalized documents into ClickHouse, and returns the transformed
records back to Firehose so that Firehose can write them to S3.
"""
import base64
import json
import logging
import os
import gzip
from datetime import datetime, timezone
from typing import Any, Iterable, List

# Shared utilities are available when the project root is on sys.path (tests)
# or when included in the Lambda deployment package.
try:
    from src.shared.logger import get_logger
    from src.shared.clickhouse_client import ClickHouseClient
except ImportError:
    # Fallback: shared code bundled alongside this handler in the Lambda zip
    try:
        from shared.logger import get_logger          # type: ignore[no-redef]
        from shared.clickhouse_client import ClickHouseClient  # type: ignore[no-redef]
    except ImportError:
        # Last-resort: plain stdlib logger so the Lambda can still function
        def get_logger(name: str) -> logging.Logger:  # type: ignore[misc]
            logger = logging.getLogger(name)
            if not logger.handlers:
                handler = logging.StreamHandler()
                logger.addHandler(handler)
                logger.setLevel(logging.INFO)
            return logger

        class _StubCH:  # type: ignore[misc]
            def insert(self, *_, **__):
                pass

        ClickHouseClient = _StubCH  # type: ignore[assignment,misc]

logger = get_logger("log-normalizer")

# Canonical fields required in every normalized log document
CANONICAL_FIELDS = (
    "timestamp",
    "account_id",
    "region",
    "service",
    "environment",
    "log_level",
    "message",
    "deployment_version",
    "deployment_timestamp",
    "related_events",
)

_LOG_LEVEL_KEYWORDS = {
    "error": "ERROR",
    "err": "ERROR",
    "warn": "WARN",
    "warning": "WARN",
    "info": "INFO",
    "debug": "DEBUG",
    "critical": "CRITICAL",
    "fatal": "CRITICAL",
}

# Module-level singleton; replaced in tests via ``handler._clickhouse = mock``
_clickhouse = None


def _get_clickhouse():
    global _clickhouse
    if _clickhouse is None:
        if ClickHouseClient is None:
            raise RuntimeError("ClickHouseClient is not available")
        _clickhouse = ClickHouseClient()
    return _clickhouse


def _extract_log_level(raw: dict[str, Any]) -> str:
    """Extract log level from various common field names."""
    for field in ("log_level", "level", "severity", "logLevel"):
        value = raw.get(field, "")
        if value:
            return _LOG_LEVEL_KEYWORDS.get(str(value).lower(), str(value).upper())

    # Try to infer from message text
    message = str(raw.get("message", "")).lower()
    for keyword, level in _LOG_LEVEL_KEYWORDS.items():
        if keyword in message:
            return level

    return "INFO"


def _normalize_record(raw: dict[str, Any]) -> dict[str, Any]:
    """Transform a raw log dict to the canonical schema."""
    now = datetime.now(timezone.utc).isoformat()

    return {
        "timestamp": raw.get("timestamp") or raw.get("@timestamp") or now,
        "account_id": raw.get("account_id") or raw.get("accountId") or "unknown",
        "region": raw.get("region") or raw.get("awsRegion") or os.environ.get("AWS_REGION", "unknown"),
        "service": raw.get("service") or raw.get("logGroup", "").split("/")[-1] or "unknown",
        "environment": raw.get("environment") or os.environ.get("ENVIRONMENT", "unknown"),
        "log_level": _extract_log_level(raw),
        "message": raw.get("message") or raw.get("msg") or "",
        "deployment_version": raw.get("deployment_version") or raw.get("appVersion") or "unknown",
        "deployment_timestamp": raw.get("deployment_timestamp") or "",
        "related_events": raw.get("related_events") or [],
        # Preserve extra fields so no data is lost
        "_raw": json.dumps({k: v for k, v in raw.items() if k not in CANONICAL_FIELDS}),
    }


def _insert_to_clickhouse(docs: list[dict[str, Any]]) -> None:
    """Insert normalized documents to ClickHouse."""
    try:
        _get_clickhouse().insert("logs", docs)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Failed to insert %d document(s) to ClickHouse: %s", len(docs), exc)


def _decode_record_data(data_b64: str) -> bytes:
    """Decode base64 data from Firehose record."""
    return base64.b64decode(data_b64)


def _parse_cwl_subscription(payload: bytes) -> Iterable[dict[str, Any]]:
    """Parse CloudWatch Logs subscription payload (gzipped JSON).

    Returns iterable of raw log dicts.
    """
    try:
        if payload.startswith(b"\x1f\x8b"):
            payload = gzip.decompress(payload)
        text = payload.decode("utf-8")
    except Exception:
        # If decode fails, try decompressing even if magic bytes were missing
        try:
            payload = gzip.decompress(payload)
            text = payload.decode("utf-8")
        except Exception:
            raise

    body = json.loads(text)

    log_group = body.get("logGroup", "")
    log_stream = body.get("logStream", "")
    for event in body.get("logEvents", []) or []:
        msg = event.get("message", "")
        # Try to parse message as JSON; fall back to plain text field
        try:
            parsed = json.loads(msg)
            if isinstance(parsed, dict):
                raw = parsed
            else:
                raw = {"message": msg}
        except json.JSONDecodeError:
            raw = {"message": msg}
        raw.setdefault("logGroup", log_group)
        raw.setdefault("logStream", log_stream)
        yield raw


def _process_record(record: dict[str, Any]) -> dict[str, Any]:
    """Process a single Firehose record.

    Returns a Firehose-compatible result dict with status
    ``Ok``, ``Dropped``, or ``ProcessingFailed``.
    """
    record_id = record["recordId"]
    try:
        payload = _decode_record_data(record["data"])

        if not payload.strip():
            return {"recordId": record_id, "result": "Dropped", "data": record["data"]}

        raw_docs: List[dict[str, Any]] = []
        # CWL subscription delivers gzipped JSON with a logEvents array.
        # If CWL parsing raises an exception the payload is malformed; record it
        # so that a plain-JSON fallback failure can escalate to ProcessingFailed.
        _cwl_exc: Exception | None = None
        try:
            raw_docs = list(_parse_cwl_subscription(payload))
        except Exception as exc:
            _cwl_exc = exc

        if not raw_docs:
            # Fall back to plain JSON (non-CWL Firehose records or CWL with no events).
            try:
                raw_json = json.loads(payload.decode("utf-8").strip())
                if isinstance(raw_json, dict):
                    raw_docs = [raw_json]
            except Exception:
                if _cwl_exc is not None:
                    # Both CWL and plain JSON parsing failed → propagate for ProcessingFailed
                    raise _cwl_exc
                raw_docs = []

        if not raw_docs:
            return {
                "recordId": record_id,
                "result": "Dropped",
                "data": record["data"],
            }

        normalized_docs = [_normalize_record(raw) for raw in raw_docs]
        _insert_to_clickhouse(normalized_docs)

        # Firehose supports returning multiple newline-delimited records in one output record
        output_blob = "\n".join(json.dumps(doc) for doc in normalized_docs) + "\n"
        encoded = base64.b64encode(output_blob.encode("utf-8")).decode("utf-8")

        return {
            "recordId": record_id,
            "result": "Ok",
            "data": encoded,
        }
    except Exception as exc:  # noqa: BLE001
        logger.error("Unexpected error processing Firehose record %s: %s", record_id, exc)
        return {
            "recordId": record_id,
            "result": "ProcessingFailed",
            "data": record["data"],
        }


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Firehose data transformation entry point.

    Args:
        event: Firehose invocation event containing ``records`` list.
        context: Lambda context object (unused).

    Returns:
        Dict with ``records`` list in Firehose transform response format.
    """
    records = event.get("records", [])
    logger.info("Processing Firehose batch of %d records", len(records))

    results = [_process_record(r) for r in records]

    ok = sum(1 for r in results if r["result"] == "Ok")
    failed = sum(1 for r in results if r["result"] == "ProcessingFailed")
    dropped = sum(1 for r in results if r["result"] == "Dropped")
    logger.info("Firehose batch complete: ok=%d failed=%d dropped=%d", ok, failed, dropped)

    return {"records": results}
