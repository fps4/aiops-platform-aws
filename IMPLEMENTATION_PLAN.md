- Enables "this happened before" context

**Files to Modify**:
- `/src/orchestration/lambda/orchestrator/historical_agent.py` (add DynamoDB queries)

**Files to Create**:
- Tests in `/tests/unit/test_orchestration_agents.py`

**Validation**:
- Test cases pass with mock DynamoDB data
- `similar_incidents` field populated with 7-day history

---

#### **Task 5: Add Bedrock Fallback & Cost Tracking** 🎯 MEDIUM PRIORITY
**Dependency**: Task 4 (agents working)  
**Effort**: 6 hours  
**Risk Mitigation**: Production resilience + compliance

**What to implement**:

Expand `/src/shared/bedrock_client.py`:

```python
class BedrockClient:
    def __init__(self, model_id: str, cost_per_1k_input: float = 0.003, cost_per_1k_output: float = 0.015):
        # ... existing init ...
        self.cost_per_1k_input = cost_per_1k_input
        self.cost_per_1k_output = cost_per_1k_output

    def invoke(self, prompt: str) -> str:
        """Invoke Bedrock with cost tracking and retry logic."""
        try:
            response = self._bedrock.invoke_model(...)
            
            # Parse usage
            usage = response.get("usage", {})
            input_tokens = usage.get("input_tokens", 0)
            output_tokens = usage.get("output_tokens", 0)
            cost = (input_tokens * self.cost_per_1k_input / 1000) + \
                   (output_tokens * self.cost_per_1k_output / 1000)
            
            # Track cost to CloudWatch
            self._cw.put_metric_data(
                Namespace="AIOps/Bedrock",
                MetricData=[
                    {"MetricName": "TokenCost", "Value": cost, "Unit": "None"},
                    {"MetricName": "InputTokens", "Value": input_tokens},
                    {"MetricName": "OutputTokens", "Value": output_tokens},
                ]
            )
            
            return response_text
        except Exception as e:
            logger.error(f"Bedrock unavailable: {e}")
            raise
```

Add to each agent (`detection_agent.py`, `rca_agent.py`, etc.):

```python
def run(ctx: dict) -> dict:
    # ... existing logic ...
    try:
        bedrock = create_bedrock_client("rca")
        response = bedrock.invoke(prompt)
    except Exception as exc:
        logger.warning(f"Bedrock unavailable, using degraded mode: {exc}")
        ctx["rca_fallback_reason"] = str(exc)
        # Return sensible defaults
```

**Tests to Add**:
```python
class TestBedrockCostTracking:
    def test_cost_calculation(self, mock_cloudwatch):
        client = BedrockClient(model_id="...")
        client.invoke("test prompt")
        
        assert mock_cloudwatch.put_metric_data.called
        call_args = mock_cloudwatch.put_metric_data.call_args
        metrics = call_args[1]["MetricData"]
        assert any(m["MetricName"] == "TokenCost" for m in metrics)

    def test_bedrock_exception_fallback(self, mock_bedrock_unavailable):
        ctx = {"anomaly": {"service": "api"}}
        result = rca_agent.run(ctx)
        
        assert result["root_cause_analysis"]["confidence"] == "low"
        assert "rca_fallback_reason" in result
```

**Why Priority**:
- Production operational requirement (cost visibility)
- Blocks Phase 1 feature "Cost Tracking & Limits"
- Enables budget alarms

**Files to Modify**:
- `/src/shared/bedrock_client.py` (add CloudWatch metrics, retry logic)
- `/src/orchestration/lambda/orchestrator/rca_agent.py` (exception handling)
- `/src/orchestration/lambda/orchestrator/correlation_agent.py` (exception handling)
- `/src/orchestration/lambda/orchestrator/recommendation_agent.py` (exception handling)

**Validation**:
- CloudWatch metrics emitted on Bedrock calls
- Agents return degraded responses (not exceptions) on Bedrock failure
- Cost metrics visible in CloudWatch dashboard

---

### **PHASE C: Integration & System Testing**

#### **Task 6: Create Integration Test Suite** 🎯 HIGH PRIORITY
**Dependency**: Task 2 (test framework)  
**Effort**: 8-10 hours  
**Risk Mitigation**: Cross-component validation before prod

**What to implement**:

Create `/tests/integration/test_full_pipeline.py`:

```python
@pytest.mark.integration
class TestFullAnomalyPipeline:
    """End-to-end: anomaly creation → orchestrator → Slack notification."""
    
    def test_anomaly_to_slack_workflow(self, aws_dynamodb_local, mock_bedrock, mock_slack):
        """
        1. Write anomaly to DynamoDB
        2. Trigger orchestrator Lambda
        3. Verify Slack notification sent
        """
        # Setup: Create anomaly in DynamoDB
        anomaly = {
            "anomaly_id": "test-001",
            "service": "api-gateway",
            "account_id": "123456789012",
            "severity": "high",
            "rule_type": "latency_regression",
            "description": "Latency spike detected",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "open",
        }
        
        anomalies_table.put_item(Item=anomaly)
        
        # Simulate DynamoDB Stream event
        event = {
            "Records": [{
                "eventName": "INSERT",
                "dynamodb": {
                    "NewImage": _dynamodb_item_to_stream_format(anomaly)
                }
            }]
        }
        
        # Execute orchestrator
        from orchestrator.handler import lambda_handler
        result = lambda_handler(event, None)
        
        # Verify Slack called
        assert mock_slack.post_message.called
        call_args = mock_slack.post_message.call_args
        payload = call_args[1]["blocks"]
        assert any("latency_regression" in str(block) for block in payload)

    def test_detection_agent_enriches_anomaly(self, mock_clickhouse, mock_dynamodb):
        """Detection agent finds recent ERROR logs and adds to context."""
        # Setup: Mock ClickHouse with recent error logs
        mock_clickhouse.query.return_value = [
            {"timestamp": "...", "message": "Connection timeout", "log_level": "ERROR"},
        ]
        
        from orchestration.lambda.orchestrator.detection_agent import run
        ctx = {
            "anomaly": {
                "service": "api-gateway",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        }
        
        result = run(ctx)
        
        assert "detection_summary" in result
        assert result["detection_summary"]["error_log_count"] > 0

    def test_correlation_agent_finds_related_anomalies(self, mock_dynamodb):
        """Correlation agent identifies multiple service failures in same timeframe."""
        # Setup: DynamoDB has 3 recent anomalies on same service
        mock_dynamodb.scan.return_value = {
            "Items": [
                {"anomaly_id": "a1", "rule_type": "error_rate"},
                {"anomaly_id": "a2", "rule_type": "traffic_drop"},
                {"anomaly_id": "a3", "rule_type": "error_rate"},
            ]
        }
        
        from orchestration.lambda.orchestrator.correlation_agent import run
        ctx = {"anomaly": {"service": "api-gateway"}}
        result = run(ctx)
        
        assert len(result["correlated_anomalies"]) == 3
        assert result["correlation_analysis"]["pattern"] != "isolated"

    def test_rca_agent_generates_root_cause(self, mock_bedrock):
        """RCA agent calls Bedrock and returns structured output."""
        mock_bedrock.invoke_model.return_value = {
            "body": json.dumps({
                "root_cause": "Deployment v2.1 introduced connection pooling bug",
                "confidence": "high",
                "contributing_factors": ["recent_deployment", "db_timeout"],
            })
        }
        
        from orchestration.lambda.orchestrator.rca_agent import run
        ctx = {
            "anomaly": {"service": "api-gateway"},
            "detection_summary": {...},
            "correlation_analysis": {...},
            "historical_patterns": {...},
        }
        
        result = run(ctx)
        
        assert result["root_cause_analysis"]["confidence"] == "high"
        assert "deployment" in result["root_cause_analysis"]["root_cause"].lower()
```

Create `/tests/integration/test_detection_pipeline.py`:

```python
@pytest.mark.integration
class TestDetectionPipeline:
    def test_rule_detection_writes_to_dynamodb(self, mock_clickhouse, mock_dynamodb):
        """Rule detection finds error_rate > 5%, writes anomaly."""
        from detection.rules.handler import _check_error_rate
        
        mock_clickhouse.query.return_value = [{"total": 1000, "error_count": 100}]  # 10% error rate
        
        result = _check_error_rate(mock_clickhouse, mock_dynamodb, "api", "123456789012", {
            "error_rate_threshold": 0.05,
            "cooldown_seconds": 300,
        })
        
        assert result is not None
        assert result["severity"] == "high"
        assert mock_dynamodb.put_item.called  # Anomaly persisted

    def test_statistical_detection_detects_spikes(self, mock_clickhouse, mock_dynamodb):
        """Statistical detection with STL finds 2σ spike."""
        from detection.statistical.main import run_detection
        
        # Mock 7-day baseline + spike
        mock_clickhouse.query.return_value = [
            {"ts": "...", "value": 100.0},  # x14
            {"ts": "...", "value": 500.0},  # spike
        ]
        
        count = run_detection()
        
        assert count >= 1
        assert mock_dynamodb.put_item.called
```

Create `/tests/integration/conftest.py`:

```python
import pytest
import boto3
from moto import mock_dynamodb, mock_s3
import os

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("AWS_REGION", "eu-central-1")
os.environ.setdefault("DYNAMODB_ANOMALIES_TABLE", "test-anomalies")
os.environ.setdefault("DYNAMODB_POLICY_TABLE", "test-policies")
os.environ.setdefault("DYNAMODB_EVENTS_TABLE", "test-events")

@pytest.fixture
@mock_dynamodb
def aws_dynamodb_local():
    """DynamoDB local for integration tests."""
    dynamodb = boto3.resource("dynamodb", region_name="eu-central-1")
    
    # Create tables
    for table_name in ["test-anomalies", "test-policies", "test-events"]:
        dynamodb.create_table(
            TableName=table_name,
            KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
    
    yield dynamodb
```

**Why High Priority**:
- No integration tests currently (directory empty)
- Validates multi-component workflows
- Catches cross-module bugs before prod
