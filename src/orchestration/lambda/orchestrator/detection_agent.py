"""Detection Agent — enriches the anomaly with recent error logs from ClickHouse."""
import os
from datetime import datetime, timedelta, timezone

try:
    from shared.clickhouse_client import ClickHouseClient
    from shared.logger import get_logger
except ImportError:
    ClickHouseClient = None  # type: ignore[assignment,misc]
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
    if ClickHouseClient is not None:
        try:
            client = ClickHouseClient()
            anomaly_time = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            window_start = (anomaly_time - timedelta(minutes=30)).strftime("%Y-%m-%d %H:%M:%S")
            window_end = (anomaly_time + timedelta(minutes=5)).strftime("%Y-%m-%d %H:%M:%S")

            sql = f"""
                SELECT *
                FROM aiops.logs
                WHERE service = '{service}'
                  AND log_level IN ('ERROR', 'CRITICAL')
                  AND timestamp >= '{window_start}'
                  AND timestamp <= '{window_end}'
                ORDER BY timestamp DESC
                LIMIT 50
            """
            recent_logs = client.query(sql)
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
