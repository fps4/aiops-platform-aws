# Local Development Guide

This guide covers how to develop and test AIOps Platform components locally using AWS Bedrock.

## Prerequisites

- Python 3.13+
- AWS CLI configured with credentials
- Access to AWS Bedrock in `eu-central-1` region
- Infrastructure deployed via Terraform (see [terraform/README.md](../terraform/README.md))

## Initial Setup

### 1. Enable Bedrock Models

Make sure you have access to Claude models in AWS Bedrock:

1. Go to AWS Console → Bedrock → Model access
2. Request access to:
   - Claude 3.5 Sonnet v2
   - Claude 3.5 Haiku
3. Wait for approval (usually instant for Anthropic models)

### 2. Configure AWS Credentials

```bash
# Option 1: Use AWS CLI profile
export AWS_PROFILE=your-profile
export AWS_REGION=eu-central-1

# Option 2: Use access keys (not recommended for production)
export AWS_ACCESS_KEY_ID=your-key-id
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_REGION=eu-central-1
```

### 3. Create Local Environment File

```bash
# Copy example environment file
cp .env.example .env

# Fetch configuration from deployed infrastructure
./scripts/get-config.sh dev

# Edit .env with your values
vim .env
```

### 4. Install Python Dependencies

```bash
# Create virtual environment
python3.13 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies (when requirements.txt is available)
pip install boto3 python-dotenv
```

## Using Bedrock Locally

### Quick Test

```bash
# Test Bedrock connectivity
python src/shared/bedrock_client.py
```

Expected output:
```
Testing Bedrock Client...
============================================================
Initialized Bedrock client: model=anthropic.claude-3-5-sonnet-20241022-v2:0, region=eu-central-1, max_tokens=4096
Model: anthropic.claude-3-5-sonnet-20241022-v2:0
Response: High API latency is typically caused by ...
Usage: {'input_tokens': 45, 'output_tokens': 120}
============================================================
```

### In Your Code

```python
from src.shared.bedrock_client import create_bedrock_client

# Create client for RCA agent
client = create_bedrock_client(agent_type="rca")

# Simple invocation
response = client.invoke(
    prompt="Analyze this error: Connection timeout after 30s",
    system_prompt="You are an expert SRE doing root cause analysis."
)

print(response['text'])

# Streaming response
for chunk in client.invoke_streaming(
    prompt="Explain the most common causes of database deadlocks"
):
    print(chunk, end='', flush=True)
```

### Load Configuration from SSM

```python
# Automatically fetch model IDs from Parameter Store
client = BedrockClient(use_ssm=True, environment="dev")

response = client.invoke("What causes memory leaks in Python?")
print(response['text'])
```

## Configuration Options

### Environment Variables

```bash
# AWS
AWS_REGION=eu-central-1
AWS_PROFILE=default

# Bedrock
BEDROCK_RCA_MODEL_ID=anthropic.claude-3-5-sonnet-20241022-v2:0
BEDROCK_CORRELATION_MODEL_ID=anthropic.claude-3-5-haiku-20241022-v1:0
BEDROCK_MAX_TOKENS=4096
BEDROCK_TEMPERATURE=0.7

# Project
ENVIRONMENT=dev
PROJECT_PREFIX=aiops-platform
```

### Changing Models

To use different Bedrock models:

1. **For local testing**: Update `.env` file
2. **For deployed agents**: Update SSM parameters:
   ```bash
   aws ssm put-parameter \
     --name "/aiops-platform/dev/bedrock/rca_model_id" \
     --value "anthropic.claude-3-opus-20240229" \
     --type String \
     --overwrite
   ```

### Available Claude Models

| Model | Model ID | Use Case |
|-------|----------|----------|
| Claude 3.5 Sonnet v2 | `anthropic.claude-3-5-sonnet-20241022-v2:0` | RCA, Remediation (best reasoning) |
| Claude 3.5 Haiku | `anthropic.claude-3-5-haiku-20241022-v1:0` | Correlation, Quick analysis (fastest) |
| Claude 3 Opus | `anthropic.claude-3-opus-20240229` | Complex investigations (most capable) |

## Testing Different Agents

```python
# RCA Agent (detailed root cause analysis)
rca_client = create_bedrock_client(agent_type="rca")
rca_response = rca_client.invoke(
    prompt="High CPU usage on api-server pods...",
    system_prompt="You are performing deep root cause analysis."
)

# Correlation Agent (fast pattern matching)
corr_client = create_bedrock_client(agent_type="correlation")
corr_response = corr_client.invoke(
    prompt="Find patterns in these 5 error messages...",
    temperature=0.3  # Lower temperature for more deterministic results
)

# Remediation Agent (action recommendations)
rem_client = create_bedrock_client(agent_type="remediation")
rem_response = rem_client.invoke(
    prompt="Database connection pool exhausted. Suggest fixes.",
    system_prompt="Provide actionable remediation steps."
)
```

## Cost Management

### Token Usage Tracking

```python
response = client.invoke("Your prompt here")

print(f"Input tokens: {response['usage']['input_tokens']}")
print(f"Output tokens: {response['usage']['output_tokens']}")
```

### Estimated Costs (as of 2026)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Claude 3.5 Sonnet v2 | $3.00 | $15.00 |
| Claude 3.5 Haiku | $0.80 | $4.00 |
| Claude 3 Opus | $15.00 | $75.00 |

**Tip**: Use Haiku for simple/repetitive tasks, Sonnet for complex reasoning.

## Troubleshooting

### "Access Denied" Error

```
botocore.exceptions.ClientError: An error occurred (AccessDeniedException)
```

**Solution**: 
1. Check Bedrock model access: AWS Console → Bedrock → Model access
2. Verify IAM permissions include `bedrock:InvokeModel`
3. Confirm region is `eu-central-1` (or update config)

### "Model Not Found"

```
ValidationException: The provided model identifier is invalid
```

**Solution**: Double-check model ID in `.env` matches available models

### "Throttling Exception"

```
ThrottlingException: Rate exceeded
```

**Solution**: Add retry logic or request quota increase via AWS Support

## Next Steps

- See [solution-design.md](solution-design.md) for agent architecture
- Check [FEATURES.md](../FEATURES.md) for AI/ML capabilities roadmap
