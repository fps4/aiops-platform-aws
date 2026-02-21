"""Recommendation Agent — generates remediation steps via Bedrock Claude Sonnet (temperature 0.3)."""
import json
import os

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

logger = get_logger("recommendation-agent")

_RECOMMEND_PROMPT = """\
You are an AWS operations expert. Generate actionable remediation recommendations.

Service: {service}
Anomaly Type: {rule_type}
Severity: {severity}
Root Cause: {root_cause}
Contributing Factors: {factors}
Recurring: {recurring} (occurred {freq} times in the last 30 days)

Respond with JSON only:
{{
  "immediate_actions": ["action1", "action2"],
  "long_term_fixes": ["fix1", "fix2"],
  "runbook_steps": ["step1", "step2", "step3"],
  "escalation_required": false,
  "estimated_resolution_time": "X minutes"
}}"""


def run(ctx: dict) -> dict:
    anomaly = ctx["anomaly"]
    rca = ctx.get("root_cause_analysis", {})
    history = ctx.get("historical_patterns", {})

    recommendations: dict = {
        "immediate_actions": ["Investigate manually — AI recommendations unavailable"],
        "long_term_fixes": [],
        "runbook_steps": [],
        "escalation_required": True,
        "estimated_resolution_time": "unknown",
    }

    if create_bedrock_client is not None:
        try:
            bedrock = create_bedrock_client("remediation")
            prompt = _RECOMMEND_PROMPT.format(
                service=anomaly.get("service", "unknown"),
                rule_type=anomaly.get("rule_type", "unknown"),
                severity=anomaly.get("severity", "medium"),
                root_cause=rca.get("root_cause", "unknown"),
                factors=json.dumps(rca.get("contributing_factors", [])),
                recurring=history.get("is_recurring", False),
                freq=history.get("frequency_30d", 0),
            )
            response = bedrock.invoke(prompt)
            raw = response.strip()
            if raw.startswith("```"):
                raw = raw.split("```")[1].lstrip("json").strip()
            recommendations = json.loads(raw)
        except json.JSONDecodeError:
            recommendations["immediate_actions"] = [response]  # type: ignore[possibly-undefined]
        except Exception as exc:
            logger.error("Recommendation Bedrock call failed", extra={"error": str(exc)})

    ctx["recommendations"] = recommendations
    return ctx
