# Agentic Orchestration

## Overview

A single **orchestrator Lambda** is triggered by DynamoDB Streams on the `anomalies` table. It runs the full agentic pipeline sequentially within one invocation. Each agent is a Python module with a `run()` interface — clean separation without service boundaries.

## Why a Single Lambda over Step Functions

- **Simpler**: No state machine JSON to maintain, no additional service to manage
- **Fewer resources**: One Lambda, one IAM role, one CloudWatch log group
- **Sufficient**: The pipeline is linear (no branching/parallelism), completes in ~10–30 seconds
- **Auditable**: Structured JSON logging provides the audit trail
- **Retriable**: DynamoDB Streams provides built-in retry on failure
- **Migratable**: If branching or parallel execution is needed later, the modular agent interfaces make Step Functions migration straightforward

## Orchestrator Implementation

```python
def lambda_handler(event, context):
    anomaly = parse_dynamodb_stream(event)

    # Agent 1: Deduplicate and suppress
    filtered = detection_agent.run(anomaly)
    if filtered.suppressed:
        logger.info("Anomaly suppressed", anomaly_id=anomaly["anomaly_id"])
        return

    # Agent 2: Correlate with infra/deploy events
    enriched = correlation_agent.run(filtered)

    # Agent 3: Find similar past incidents
    history = historical_compare_agent.run(enriched)

    # Agent 4: Root cause analysis (calls Bedrock)
    rca = rca_agent.run(enriched, history)

    # Agent 5: Map to runbooks and recommendations
    recommendations = recommendation_agent.run(rca)

    # Send alert
    slack_notifier.send(rca, recommendations)
```

## Agent Module Interface

```python
# Each agent follows this pattern: src/agents/{agent_name}/agent.py
class BaseAgent(ABC):
    @abstractmethod
    def run(self, *args) -> dict:
        """Execute agent logic, return structured result."""
        pass
```

## Agent Responsibilities

| Agent                     | Module                        | Function                                                           | Output                          | AI Provider        | Phase   |
|---------------------------|-------------------------------|--------------------------------------------------------------------|---------------------------------|--------------------|---------|
| **Detection Agent**       | `agents/detection`            | Deduplicate, apply suppression rules, decide escalation           | Filtered anomaly                | None               | **MVP** |
| **Correlation Agent**     | `agents/correlation`          | Join infra events, deployment events, related anomalies            | Enriched anomaly + context      | Bedrock (optional) | **MVP** |
| **Historical Compare**    | `agents/historical_compare`   | Find similar past incidents, compare current vs last deployment    | Similarity scores, past RCAs    | None (query)       | **MVP** |
| **RCA Agent**             | `agents/rca`                  | Investigate pre-defined scenarios, generate hypothesis with confidence | Probable root cause + evidence | **Bedrock Claude** | **MVP** |
| **Recommendation Agent**  | `agents/recommendation`       | Map cause to runbooks, suggest next steps                          | Recommendations + links         | Bedrock (optional) | **MVP** |

## RCA Agent: Pre-Defined Investigation Scenarios

1. **Deployment Correlation**: Did a deployment happen in the last 30 minutes? Evidence: deployment event, code diff, config changes.
2. **Infrastructure Change**: Did autoscaling, instance replacement, or AZ failure occur? Evidence: EC2 events, ELB health checks, CloudWatch alarms.
3. **Dependency Failure**: Is a downstream service experiencing errors or latency? Evidence: correlated anomalies across services, API gateway metrics.
4. **Resource Exhaustion**: Are CPU, memory, disk, or network limits hit? Evidence: CloudWatch metrics, OOM logs, throttling errors.
5. **Security/Access**: Did an IAM policy, security group, or network ACL change? Evidence: CloudTrail events, VPC flow logs.

## RCA Agent: AI Provider Call (example)

```python
context = {
    "anomaly": {...},
    "deployment_events": [...],
    "related_logs": [...],
    "similar_past_incidents": [...]
}

prompt = f"""
Analyze the following anomaly and determine probable root cause.

Anomaly: {context['anomaly']}
Recent Deployments: {context['deployment_events']}
Related Error Logs: {context['related_logs']}
Similar Past Incidents: {context['similar_past_incidents']}

Provide:
1. Probable root cause (1-2 sentences)
2. Confidence level (low/medium/high) with reasoning
3. Key evidence supporting hypothesis
4. Alternative explanations (if confidence < high)

Format as JSON.
"""

response = ai_provider.generate(
    agent_type="rca",   # selects provider from policy config
    prompt=prompt,
    max_tokens=500,
    temperature=0.2     # deterministic for RCA
)

audit_log(prompt, response)   # logged to S3 for compliance
return parse_rca_json(response)
```
