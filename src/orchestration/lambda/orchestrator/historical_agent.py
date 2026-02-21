"""Historical Compare Agent — compares current anomaly against 30-day history in DynamoDB."""
import os
from datetime import datetime, timedelta, timezone

import boto3

try:
    from shared.logger import get_logger
except ImportError:
    import logging

    def get_logger(name: str):  # type: ignore[misc]
        logger = logging.getLogger(name)
        if not logger.handlers:
            logger.addHandler(logging.StreamHandler())
            logger.setLevel(logging.INFO)
        return logger

logger = get_logger("historical-compare-agent")

_dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "eu-central-1"))


def run(ctx: dict) -> dict:
    anomaly = ctx["anomaly"]
    service = anomaly.get("service", "unknown")
    rule_type = anomaly.get("rule_type", "unknown")

    historical: list = []
    table_name = os.environ.get("DYNAMODB_ANOMALIES_TABLE")
    if table_name:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
        table = _dynamodb.Table(table_name)
        try:
            resp = table.scan(
                FilterExpression="service = :svc AND rule_type = :rt AND #ts >= :cutoff",
                ExpressionAttributeNames={"#ts": "timestamp"},
                ExpressionAttributeValues={
                    ":svc": service,
                    ":rt": rule_type,
                    ":cutoff": cutoff,
                },
                Limit=50,
            )
            historical = resp.get("Items", [])
        except Exception as exc:
            logger.warning("Could not query historical anomalies", extra={"error": str(exc)})

    severities = [h.get("severity", "medium") for h in historical]
    freq = len(historical)

    ctx["historical_patterns"] = {
        "frequency_30d": freq,
        "is_recurring": freq > 3,
        "severity_distribution": {
            "critical": severities.count("critical"),
            "high": severities.count("high"),
            "medium": severities.count("medium"),
        },
        "first_seen": min((h["timestamp"] for h in historical), default=None),
        "last_seen": max((h["timestamp"] for h in historical), default=None),
    }
    return ctx
