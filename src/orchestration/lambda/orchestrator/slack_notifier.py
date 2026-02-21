"""Slack Notifier — formats RCA workflow results and posts to Slack via webhook."""
import json
import os
import urllib.parse
import urllib.request
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

logger = get_logger("slack-notifier")

_SEVERITY_EMOJI = {"critical": ":red_circle:", "high": ":large_orange_circle:", "medium": ":large_yellow_circle:"}
_SEVERITY_COLOR = {"critical": "#FF0000", "high": "#FF6600", "medium": "#FFCC00"}


def _webhook_url() -> str:
    secret_arn = os.environ.get("SLACK_WEBHOOK_SECRET_ARN", "")
    if not secret_arn:
        raise ValueError("SLACK_WEBHOOK_SECRET_ARN not configured")
    sm = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "eu-central-1"))
    secret = json.loads(sm.get_secret_value(SecretId=secret_arn)["SecretString"])
    return secret["webhook_url"]


def _build_dashboard_url(opensearch_endpoint: str, anomaly: dict) -> str:
    """Build a deep-link URL to the RCA Evidence Explorer dashboard.

    Adds a ±30-minute time window around the anomaly timestamp and filters
    by service so the dashboard opens pre-filtered to the relevant incident.
    """
    if not opensearch_endpoint:
        return ""

    anomaly_id = anomaly.get("anomaly_id", "")
    service = anomaly.get("service", "")
    ts_str = anomaly.get("timestamp", "")

    try:
        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        ts = datetime.now(timezone.utc)

    time_from = (ts - timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    time_to = (ts + timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%S.000Z")

    filters = (
        f"!((query:(match_phrase:(service:'{service}'))))"
        if service
        else "!()"
    )
    global_state = f"(time:(from:'{time_from}',to:'{time_to}'))"
    app_state = f"(filters:{filters})"

    base = f"https://{opensearch_endpoint}/_dashboards/app/dashboards"
    params = urllib.parse.urlencode({
        "_g": global_state,
        "_a": app_state,
    })
    return f"{base}#/view/rca-evidence-explorer?{params}"


def notify(ctx: dict) -> None:
    anomaly = ctx["anomaly"]
    rca = ctx.get("root_cause_analysis", {})
    recs = ctx.get("recommendations", {})
    history = ctx.get("historical_patterns", {})

    severity = anomaly.get("severity", "medium")
    service = anomaly.get("service", "unknown")
    account = anomaly.get("account_id", "unknown")
    env = anomaly.get("environment", os.environ.get("ENVIRONMENT", "dev"))
    anomaly_type = anomaly.get("rule_type", "unknown")

    emoji = _SEVERITY_EMOJI.get(severity, ":white_circle:")
    color = _SEVERITY_COLOR.get(severity, "#CCCCCC")

    immediate = "\n".join(f"• {a}" for a in recs.get("immediate_actions", [])[:3])
    long_term = "\n".join(f"• {f}" for f in recs.get("long_term_fixes", [])[:2])
    recurring_tag = (
        f"  :repeat: Recurring ({history.get('frequency_30d', 0)}x / 30d)"
        if history.get("is_recurring")
        else ""
    )
    root_cause = rca.get("root_cause", anomaly.get("description", "N/A"))
    confidence = rca.get("confidence", "N/A")

    opensearch_endpoint = os.environ.get("OPENSEARCH_ENDPOINT", "")
    dashboard_url = _build_dashboard_url(opensearch_endpoint, anomaly)

    blocks: list = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": f"{emoji} AIOps Alert [{env.upper()}]: {severity.upper()} — {service}"},
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Service:*\n{service}"},
                {"type": "mrkdwn", "text": f"*Account:*\n{account}"},
                {"type": "mrkdwn", "text": f"*Type:*\n{anomaly_type}"},
                {"type": "mrkdwn", "text": f"*Confidence:*\n{confidence}"},
            ],
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Root Cause:*\n{root_cause}{recurring_tag}",
            },
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": (
                    f"*Immediate Actions:*\n{immediate or '• See runbook'}\n\n"
                    f"*Long-term Fixes:*\n{long_term or '• N/A'}"
                ),
            },
        },
    ]

    if dashboard_url:
        blocks.append({
            "type": "actions",
            "elements": [{"type": "button", "text": {"type": "plain_text", "text": "Open Dashboard"}, "url": dashboard_url}],
        })

    payload = {"attachments": [{"color": color, "blocks": blocks}]}

    url = _webhook_url()
    if "PLACEHOLDER" in url:
        logger.warning("Slack webhook URL is a placeholder — skipping notification")
        return

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        logger.info("Slack notification sent", extra={"status": resp.status})
