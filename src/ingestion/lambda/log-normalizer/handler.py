"""Kinesis Firehose data transformation Lambda.

Decodes each Firehose record, normalizes it to the canonical log schema,
indexes the normalized document into OpenSearch, and returns the transformed
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
    from src.shared.opensearch_client import OpenSearchClient
except ImportError:
    # Fallback: shared code bundled alongside this handler in the Lambda zip
    try:
        from shared.logger import get_logger          # type: ignore[no-redef]
        from shared.opensearch_client import OpenSearchClient  # type: ignore[no-redef]
    except ImportError:
        # Last-resort: plain stdlib logger so the Lambda can still function
        def get_logger(name: str) -> logging.Logger:  # type: ignore[misc]
            logger = logging.getLogger(name)
            if not logger.handlers:
                handler = logging.StreamHandler()
                logger.addHandler(handler)
                logger.setLevel(logging.INFO)
            return logger

        class _StubOS:  # type: ignore[misc]
            def index(self, *_, **__):
                pass

        OpenSearchClient = _StubOS  # type: ignore[assignment,misc]

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

# Module-level singleton; replaced in tests via ``handler._opensearch = mock``
_opensearch = None


def _get_opensearch():
    global _opensearch
    if _opensearch is None:
        if OpenSearchClient is None:
            raise RuntimeError("OpenSearchClient is not available")
        _opensearch = OpenSearchClient()
    return _opensearch


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
        "_raw": {k: v for k, v in raw.items() if k not in CANONICAL_FIELDS},
    }


def _index_to_opensearch(doc: dict[str, Any]) -> None:
    """Index a normalized document to OpenSearch."""
    service = doc.get("service", "unknown")
    date = doc.get("timestamp", "")[:10].replace("-", ".")
    index = f"logs-{service}-{date}"
    try:
        _get_opensearch().index(index=index, doc=doc)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Failed to index document to OpenSearch: %s (index=%s)", exc, index)


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

        raw_docs: List[dict[str, Any]] = []
        # CWL subscription delivers gzipped JSON with logEvents
        try:
            raw_docs = list(_parse_cwl_subscription(payload))
        except Exception:
            # Not a CWL subscription payload; try plain JSON
            try:
                raw_json = json.loads(payload.decode("utf-8").strip())
                raw_docs = [raw_json]
            except Exception:
                raw_docs = []

        if not raw_docs:
            return {
                "recordId": record_id,
                "result": "Dropped",
                "data": record["data"],
            }

        normalized_docs = []
        for raw in raw_docs:
            normalized = _normalize_record(raw)
            _index_to_opensearch(normalized)
            normalized_docs.append(normalized)

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
