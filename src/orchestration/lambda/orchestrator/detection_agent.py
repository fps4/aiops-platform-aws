"""Detection Agent — enriches the anomaly with recent error logs from OpenSearch."""
import os
from datetime import datetime, timedelta, timezone

try:
    from shared.opensearch_client import OpenSearchClient
    from shared.logger import get_logger
except ImportError:
    OpenSearchClient = None  # type: ignore[assignment,misc]
    import logging

    def get_logger(name: str):  # type: ignore[misc]
        logger = logging.getLogger(name)
        if not logger.handlers:
            logger.addHandler(logging.StreamHandler())
            logger.setLevel(logging.INFO)
        return logger

logger = get_logger("detection-agent")


def run(ctx: dict) -> dict:
    anomaly = ctx["anomaly"]
    service = anomaly.get("service", "unknown")
    timestamp = anomaly.get("timestamp", datetime.now(timezone.utc).isoformat())

    recent_logs: list = []
    if OpenSearchClient is not None:
        try:
            client = OpenSearchClient()
            anomaly_time = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            window_start = (anomaly_time - timedelta(minutes=30)).isoformat()
            window_end = (anomaly_time + timedelta(minutes=5)).isoformat()

            query = {
                "query": {
                    "bool": {
                        "must": [
                            {"term": {"service": service}},
                            {"terms": {"log_level": ["ERROR", "CRITICAL"]}},
                            {"range": {"timestamp": {"gte": window_start, "lte": window_end}}},
                        ]
                    }
                },
                "size": 50,
                "sort": [{"timestamp": {"order": "desc"}}],
            }
            result = client.search(f"logs-{service}-*", query)
            hits = result.get("hits", {}).get("hits", [])
            recent_logs = [h["_source"] for h in hits]
        except Exception as exc:
            logger.warning("Could not fetch recent logs", extra={"error": str(exc)})

    ctx["detection_summary"] = {
        "service": service,
        "account_id": anomaly.get("account_id", ""),
        "anomaly_type": anomaly.get("rule_type", "unknown"),
        "severity": anomaly.get("severity", "medium"),
        "description": anomaly.get("description", ""),
        "recent_error_logs": recent_logs[:10],
        "error_log_count": len(recent_logs),
    }
    return ctx
