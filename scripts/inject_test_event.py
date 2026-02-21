#!/usr/bin/env python3
"""Write a synthetic anomaly to DynamoDB to trigger the orchestrator pipeline end-to-end.

The DynamoDB Stream on the anomalies table fires on INSERT, which invokes the
orchestrator Lambda.  This script short-circuits the ingestion and detection layers
so you can test the orchestration, agent pipeline, and Slack notification without
needing real traffic flowing through Firehose.

Usage:
    python scripts/inject_test_event.py [--service SERVICE] [--env ENV] [--region REGION]

Examples:
    python scripts/inject_test_event.py
    python scripts/inject_test_event.py --service payment-service --env dev
"""

import argparse
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3


def _account_id(region: str) -> str:
    return boto3.client("sts", region_name=region).get_caller_identity()["Account"]


def inject_anomaly(table_name: str, service: str, env: str, region: str) -> str:
    dynamodb = boto3.resource("dynamodb", region_name=region)
    table = dynamodb.Table(table_name)

    now = datetime.now(timezone.utc)
    anomaly_id = f"test-{uuid.uuid4().hex[:8]}"

    item = {
        "anomaly_id": anomaly_id,
        "timestamp":  now.isoformat(),
        "account_id": _account_id(region),
        "service":    service,
        "rule_type":  "statistical",
        "detection_method": "synthetic_test",
        "severity":   "high",
        "description": f"[SYNTHETIC TEST] Latency spike on {service}",
        "details": {
            "metric_field":   "p95_latency_ms",
            "z_score":        Decimal("4.5"),
            "current_value":  Decimal("1200"),
            "baseline_value": Decimal("150"),
            "deviation_pct":  Decimal("700"),
            "note": "Injected by inject_test_event.py for E2E testing",
        },
        "status":      "open",
        "environment": env,
        # Short TTL — test records expire after 1 hour
        "ttl": int(now.timestamp()) + 3600,
    }

    table.put_item(Item=item)
    return anomaly_id


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Inject a synthetic anomaly to trigger the E2E orchestration pipeline"
    )
    parser.add_argument("--service", default="api-gateway",
                        help="Service name for the synthetic anomaly (default: api-gateway)")
    parser.add_argument("--env", default=os.environ.get("ENVIRONMENT", "dev"),
                        help="Environment name (default: dev)")
    parser.add_argument("--table", default=None,
                        help="DynamoDB table name (derived from --env if not set)")
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "eu-central-1"),
                        help="AWS region (default: eu-central-1)")
    args = parser.parse_args()

    prefix = os.environ.get("PROJECT_PREFIX", "aiops")
    table_name = args.table or f"{prefix}-{args.env}-anomalies"

    print(f"→ Injecting synthetic anomaly for service '{args.service}'")
    print(f"  Table:  {table_name}")
    print(f"  Region: {args.region}")

    anomaly_id = inject_anomaly(table_name, args.service, args.env, args.region)

    print(f"\n✓ Anomaly written: {anomaly_id}")
    print(f"  The DynamoDB Stream triggers the orchestrator Lambda within seconds.")
    print(f"\n  To watch the pipeline:")
    print(f"  aws logs tail /aws/lambda/{prefix}-{args.env}-orchestrator --follow --region {args.region}")


if __name__ == "__main__":
    main()
