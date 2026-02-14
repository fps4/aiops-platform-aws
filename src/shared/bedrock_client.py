"""
AWS Bedrock Client for Local Development and Lambda

Provides unified interface to AWS Bedrock with support for:
- Local development (boto3 with credentials)
- Lambda execution (IAM role)
- Configuration from environment variables or SSM Parameter Store
"""

import os
import json
import logging
from typing import Optional, Dict, Any
import boto3
from botocore.config import Config

logger = logging.getLogger(__name__)


class BedrockClient:
    """AWS Bedrock client with automatic configuration"""
    
    def __init__(
        self,
        model_id: Optional[str] = None,
        region: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 0.7,
        use_ssm: bool = False,
        environment: str = "dev"
    ):
        """
        Initialize Bedrock client
        
        Args:
            model_id: Bedrock model ID (e.g., anthropic.claude-3-5-sonnet-20241022-v2:0)
                     If None, reads from BEDROCK_RCA_MODEL_ID env var
            region: AWS region for Bedrock (defaults to AWS_REGION or eu-central-1)
            max_tokens: Maximum tokens in response
            temperature: Model temperature (0.0-1.0)
            use_ssm: Load configuration from SSM Parameter Store
            environment: Environment name for SSM lookups (dev, staging, prod)
        """
        self.region = region or os.getenv("AWS_REGION", "eu-central-1")
        self.environment = environment
        self.project_prefix = os.getenv("PROJECT_PREFIX", "aiops-platform")
        
        # Initialize boto3 clients
        config = Config(
            region_name=self.region,
            retries={'max_attempts': 3, 'mode': 'adaptive'}
        )
        self.bedrock_runtime = boto3.client('bedrock-runtime', config=config)
        
        if use_ssm:
            self._load_from_ssm()
        else:
            self.model_id = model_id or os.getenv(
                "BEDROCK_RCA_MODEL_ID",
                "anthropic.claude-3-5-sonnet-20241022-v2:0"
            )
            self.max_tokens = int(os.getenv("BEDROCK_MAX_TOKENS", str(max_tokens)))
            self.temperature = float(os.getenv("BEDROCK_TEMPERATURE", str(temperature)))
        
        logger.info(
            f"Initialized Bedrock client: model={self.model_id}, "
            f"region={self.region}, max_tokens={self.max_tokens}"
        )
    
    def _load_from_ssm(self):
        """Load configuration from SSM Parameter Store"""
        ssm = boto3.client('ssm', region_name=self.region)
        base_path = f"/{self.project_prefix}/{self.environment}/bedrock"
        
        try:
            # Get all parameters under the bedrock path
            response = ssm.get_parameters_by_path(
                Path=base_path,
                Recursive=True,
                WithDecryption=False
            )
            
            params = {p['Name'].split('/')[-1]: p['Value'] for p in response['Parameters']}
            
            self.model_id = params.get('rca_model_id', self.model_id)
            self.max_tokens = int(params.get('max_tokens', 4096))
            self.temperature = float(params.get('temperature', 0.7))
            
            logger.info(f"Loaded Bedrock config from SSM: {base_path}")
        except Exception as e:
            logger.warning(f"Failed to load SSM parameters, using defaults: {e}")
            self.model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
            self.max_tokens = 4096
            self.temperature = 0.7
    
    def invoke(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        max_tokens: Optional[int] = None,
        temperature: Optional[float] = None
    ) -> Dict[str, Any]:
        """
        Invoke Bedrock model with Claude Messages API
        
        Args:
            prompt: User prompt/question
            system_prompt: Optional system prompt for behavior control
            max_tokens: Override default max_tokens
            temperature: Override default temperature
            
        Returns:
            Dictionary with response text and metadata
        """
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens or self.max_tokens,
            "temperature": temperature or self.temperature,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        }
        
        if system_prompt:
            request_body["system"] = system_prompt
        
        try:
            response = self.bedrock_runtime.invoke_model(
                modelId=self.model_id,
                contentType="application/json",
                accept="application/json",
                body=json.dumps(request_body)
            )
            
            response_body = json.loads(response['body'].read())
            
            return {
                "text": response_body['content'][0]['text'],
                "stop_reason": response_body.get('stop_reason'),
                "usage": response_body.get('usage', {}),
                "model_id": self.model_id
            }
            
        except Exception as e:
            logger.error(f"Bedrock invocation failed: {e}")
            raise
    
    def invoke_streaming(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        max_tokens: Optional[int] = None,
        temperature: Optional[float] = None
    ):
        """
        Invoke Bedrock model with streaming response
        
        Args:
            prompt: User prompt/question
            system_prompt: Optional system prompt
            max_tokens: Override default max_tokens
            temperature: Override default temperature
            
        Yields:
            Text chunks as they arrive
        """
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens or self.max_tokens,
            "temperature": temperature or self.temperature,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        }
        
        if system_prompt:
            request_body["system"] = system_prompt
        
        try:
            response = self.bedrock_runtime.invoke_model_with_response_stream(
                modelId=self.model_id,
                contentType="application/json",
                accept="application/json",
                body=json.dumps(request_body)
            )
            
            for event in response['body']:
                chunk = json.loads(event['chunk']['bytes'])
                
                if chunk['type'] == 'content_block_delta':
                    if 'delta' in chunk and 'text' in chunk['delta']:
                        yield chunk['delta']['text']
                        
        except Exception as e:
            logger.error(f"Bedrock streaming failed: {e}")
            raise


# Convenience function for quick usage
def create_bedrock_client(agent_type: str = "rca", **kwargs) -> BedrockClient:
    """
    Create Bedrock client configured for specific agent type
    
    Args:
        agent_type: Agent type (rca, correlation, remediation)
        **kwargs: Additional BedrockClient parameters
        
    Returns:
        Configured BedrockClient instance
    """
    model_map = {
        "rca": os.getenv("BEDROCK_RCA_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0"),
        "correlation": os.getenv("BEDROCK_CORRELATION_MODEL_ID", "anthropic.claude-3-5-haiku-20241022-v1:0"),
        "remediation": os.getenv("BEDROCK_REMEDIATION_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0"),
    }
    
    return BedrockClient(
        model_id=model_map.get(agent_type, model_map["rca"]),
        **kwargs
    )


if __name__ == "__main__":
    # Example usage for local testing
    logging.basicConfig(level=logging.INFO)
    
    print("Testing Bedrock Client...")
    print("="*60)
    
    # Test with environment variables (local dev)
    client = create_bedrock_client(agent_type="rca")
    
    response = client.invoke(
        prompt="Explain what causes high API latency in 2-3 sentences.",
        system_prompt="You are an expert SRE analyzing system performance issues."
    )
    
    print(f"Model: {response['model_id']}")
    print(f"Response: {response['text']}")
    print(f"Usage: {response['usage']}")
    print("="*60)
