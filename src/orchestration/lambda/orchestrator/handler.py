"""Orchestrator Lambda — triggered by DynamoDB Streams on the anomalies table.

Sequential pipeline:
  DetectionAgent → CorrelationAgent → HistoricalCompareAgent →
  RCAAgent (Bedrock Sonnet) → RecommendationAgent → SlackNotifier
"""
import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.types import TypeDeserializer

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

from detection_agent import run as run_detection
from correlation_agent import run as run_correlation
from historical_agent import run as run_historical
from rca_agent import run as run_rca
from recommendation_agent import run as run_recommendation
from slack_notifier import notify

logger = get_logger("orchestrator")

_dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "eu-central-1"))
_deserializer = TypeDeserializer()

PIPELINE = [
    ("detection", run_detection),
    ("correlation", run_correlation),
    ("historical_compare", run_historical),
    ("rca", run_rca),
    ("recommendation", run_recommendation),
]


def _deserialize_image(image: dict) -> dict:
    return {k: _deserializer.deserialize(v) for k, v in image.items()}


def _save_step_state(workflow_id: str, step: str, data: dict) -> None:
    table_name = os.environ.get("DYNAMODB_AGENT_STATE_TABLE")
    if not table_name:
        return
    table = _dynamodb.Table(table_name)
    table.put_item(Item={
        "workflow_id": workflow_id,
        "step_name": step,
        "status": "completed",
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "ttl": int(datetime.now(timezone.utc).timestamp()) + 86400,  # 24 h
    })


def process_anomaly(anomaly: dict) -> None:
    workflow_id = str(uuid.uuid4())
    logger.info(
        "RCA workflow started",
        extra={"workflow_id": workflow_id, "anomaly_id": anomaly.get("anomaly_id")},
    )

    ctx: dict = {"workflow_id": workflow_id, "anomaly": anomaly}

    for step_name, step_fn in PIPELINE:
        try:
            logger.info(f"Running {step_name}", extra={"workflow_id": workflow_id})
            ctx = step_fn(ctx)
            _save_step_state(workflow_id, step_name, ctx)
        except Exception as exc:
            logger.error(
                f"Step {step_name} failed — aborting workflow",
                extra={"workflow_id": workflow_id, "error": str(exc)},
            )
            raise

    try:
        notify(ctx)
    except Exception as exc:
        logger.error(
            "Slack notification failed",
            extra={"workflow_id": workflow_id, "error": str(exc)},
        )


def lambda_handler(event, context):  # noqa: ANN001
    records = event.get("Records", [])
    processed = 0
    for record in records:
        if record.get("eventName") != "INSERT":
            continue
        new_image = record.get("dynamodb", {}).get("NewImage")
        if not new_image:
            continue
        anomaly = _deserialize_image(new_image)
        process_anomaly(anomaly)
        processed += 1
    return {"processed": processed}
