"""RCA Agent — root cause analysis via Bedrock Claude Sonnet (temperature 0.2)."""
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

logger = get_logger("rca-agent")

_RCA_PROMPT = """\
You are an expert SRE performing root cause analysis on an AWS service anomaly.

Anomaly:
{anomaly}

Detection Summary:
{detection}

Correlation Analysis:
{correlation}

Historical Patterns:
{history}

Perform a thorough root cause analysis. Respond with JSON only:
{{
  "root_cause": "concise root cause statement",
  "confidence": "high|medium|low",
  "contributing_factors": ["factor1", "factor2"],
  "affected_components": ["component1"],
  "impact_assessment": "brief impact description"
}}"""


def run(ctx: dict) -> dict:
    anomaly = ctx["anomaly"]
    detection = ctx.get("detection_summary", {})
    correlation = ctx.get("correlation_analysis", {})
    history = ctx.get("historical_patterns", {})

    rca_data: dict = {
        "root_cause": "Bedrock unavailable — manual investigation required",
        "confidence": "low",
        "contributing_factors": [],
        "affected_components": [anomaly.get("service", "unknown")],
        "impact_assessment": anomaly.get("description", ""),
    }

    if create_bedrock_client is not None:
        try:
            bedrock = create_bedrock_client("rca")
            prompt = _RCA_PROMPT.format(
                anomaly=json.dumps(anomaly, indent=2, default=str),
                detection=json.dumps(detection, indent=2, default=str),
                correlation=json.dumps(correlation, indent=2, default=str),
                history=json.dumps(history, indent=2, default=str),
            )
            response = bedrock.invoke(prompt)
            raw = response.strip()
            if raw.startswith("```"):
                raw = raw.split("```")[1].lstrip("json").strip()
            rca_data = json.loads(raw)
        except json.JSONDecodeError:
            rca_data["root_cause"] = response  # type: ignore[possibly-undefined]
            rca_data["confidence"] = "low"
        except Exception as exc:
            logger.error("RCA Bedrock call failed", extra={"error": str(exc)})

    ctx["root_cause_analysis"] = rca_data
    return ctx
