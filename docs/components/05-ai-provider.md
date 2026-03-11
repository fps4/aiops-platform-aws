# AI Provider Abstraction Layer

## Interface Design

All AI calls go through a unified interface, making the provider swappable per agent type without changing orchestration logic.

```python
class AIProvider(ABC):
    @abstractmethod
    def generate(self, agent_type: str, prompt: str, max_tokens: int, temperature: float) -> str:
        pass

    @abstractmethod
    def get_cost_per_token(self) -> float:
        pass

    @abstractmethod
    def get_model_info(self) -> dict:
        pass
```

## Concrete Implementations

- `BedrockProvider`: AWS Bedrock (Claude, Titan, etc.)
- `OpenAIProvider`: OpenAI API (GPT-4, GPT-5)
- `AnthropicProvider`: Anthropic API (Claude direct)
- `SelfHostedProvider`: SageMaker endpoint or ECS service (Llama, Mistral, etc.)

## Per-Agent-Type Model Selection

Provider and model are configured in DynamoDB Policy Store, not hardcoded:

```json
{
  "ai_provider_config": {
    "rca_agent": {
      "provider": "bedrock",
      "model": "anthropic.claude-sonnet-4-5-20250929-v1:0",
      "temperature": 0.2,
      "max_tokens": 500,
      "cost_cap_per_day": 100.0
    },
    "correlation_agent": {
      "provider": "bedrock",
      "model": "anthropic.claude-haiku-4-5-20251001-v1:0",
      "temperature": 0.1,
      "max_tokens": 300,
      "cost_cap_per_day": 10.0
    },
    "recommendation_agent": {
      "provider": "bedrock",
      "model": "anthropic.claude-sonnet-4-5-20250929-v1:0",
      "temperature": 0.3,
      "max_tokens": 200,
      "cost_cap_per_day": 20.0
    }
  }
}
```

## Provider Selection Logic

```python
def get_provider_for_agent(agent_type: str) -> AIProvider:
    config = policy_store.get("ai_provider_config")[agent_type]

    if config["provider"] == "bedrock":
        return BedrockProvider(model=config["model"])
    elif config["provider"] == "self-hosted":
        return SelfHostedProvider(endpoint=config["endpoint"])
    elif config["provider"] == "openai":
        return OpenAIProvider(model=config["model"])
    else:
        raise ValueError(f"Unknown provider: {config['provider']}")
```

## Temperature Conventions

| Agent type | Temperature | Rationale |
|---|---|---|
| RCA | 0.2 | Deterministic — same inputs should produce consistent hypotheses |
| Correlation | 0.1 | Near-deterministic — fact extraction |
| Recommendation | 0.3 | Slightly creative — runbook suggestions |

## Cost Control & Audit

**Cost tracking** (per call, logged to DynamoDB):
- `agent_type`, `model`, `input_tokens`, `output_tokens`, `cost_usd`, `latency_ms`
- CloudWatch Alarm fires when daily spend exceeds `cost_cap_per_day`

**Audit log** written to S3 (queryable via Athena):

```json
{
  "timestamp": "2026-02-14T10:00:00Z",
  "agent_type": "rca_agent",
  "provider": "bedrock",
  "model": "claude-sonnet-4-5",
  "prompt": "<full prompt text>",
  "response": "<full response text>",
  "input_tokens": 1200,
  "output_tokens": 350,
  "cost_usd": 0.045,
  "latency_ms": 2300,
  "anomaly_id": "anom-abc123"
}
```

## Role and activity guide mapping

- **Platform Team**: provider selection, token caps, and model rollout governance  
  See [../guidelines/platform-team.md](../guidelines/platform-team.md)
- **Security & Compliance**: prompt/response audit and data handling controls  
  See [../guidelines/security-compliance.md](../guidelines/security-compliance.md)
- **Product Engineering Teams**: understand recommendation confidence and service context needs  
  See [../guidelines/product-engineering-teams.md](../guidelines/product-engineering-teams.md)
