"""Correlation Agent — finds related anomalies and uses Bedrock Haiku to identify patterns."""
import json
import os
from datetime import datetime, timedelta, timezone

import boto3

try:
    from shared.bedrock_client import create_bedrock_client
    from shared.logger import get_logger
except ImportError:
    create_bedrock_client = None  # type: ignore[assignment]
    import logging

    def get_logger(name: str):  # type: ignore[misc]
        logger = logging.getLogger(name)
        if not logger.handlers:
            logger.addHandler(logging.StreamHandler())
            logger.setLevel(logging.INFO)
        return logger

logger = get_logger("correlation-agent")

_dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "eu-central-1"))


def _recent_anomalies(service: str, minutes: int = 60) -> list:
    table_name = os.environ.get("DYNAMODB_ANOMALIES_TABLE")
    if not table_name:
        return []
    table = _dynamodb.Table(table_name)
    cutoff = (datetime.now(timezone.utc) - timedelta(minutes=minutes)).isoformat()
    try:
        resp = table.scan(
            FilterExpression="#ts >= :cutoff AND service = :svc",
            ExpressionAttributeNames={"#ts": "timestamp"},
            ExpressionAttributeValues={":cutoff": cutoff, ":svc": service},
            Limit=20,
        )
        return resp.get("Items", [])
    except Exception as exc:
        logger.warning("Could not query recent anomalies", extra={"error": str(exc)})
        return []


def run(ctx: dict) -> dict:
    anomaly = ctx["anomaly"]
    service = anomaly.get("service", "unknown")
    recent = _recent_anomalies(service)

    correlation_analysis: dict = {"correlated": [], "pattern": "isolated", "cascade_risk": False}

    if recent and create_bedrock_client is not None:
        try:
            bedrock = create_bedrock_client("correlation")
            prompt = (
                f"Analyze anomalies for service '{service}' and identify correlations.\n\n"
                f"Current anomaly: {json.dumps(anomaly, default=str)}\n\n"
                f"Recent anomalies (last 60 min): {json.dumps(recent, default=str)}\n\n"
                "Identify: 1) Related anomalies, 2) Patterns, 3) Cascade risk.\n"
                "Output JSON only: "
                '{"correlated": [...], "pattern": "str", "cascade_risk": false}'
            )
            response = bedrock.invoke(prompt)
            try:
                raw = response.strip()
                if raw.startswith("```"):
                    raw = raw.split("```")[1].lstrip("json").strip()
                correlation_analysis = json.loads(raw)
            except Exception:
                correlation_analysis["raw_analysis"] = response
        except Exception as exc:
            logger.warning("Bedrock correlation analysis failed", extra={"error": str(exc)})

    ctx["correlated_anomalies"] = recent
    ctx["correlation_analysis"] = correlation_analysis
    return ctx
