# AIOps Platform

**Observe - Engage - Automate**

An open-source, AWS-native observability control plane that centralizes multi-account signals, applies hybrid anomaly detection, and delivers proactive RCA alerts via Slack with AI-assisted investigation.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazon-aws)](https://aws.amazon.com/)

---

## 🎯 What is this?

The AIOps Platform autonomously **investigates anomalies before alerting you**, so you receive answers—not just notifications.

**Instead of**: "⚠️ Latency spike detected on api-gateway"  
**You get**: "🚨 Latency spike on api-gateway caused by deployment v2.3.1 (85% confidence). DB query timeout in /users endpoint. [View Dashboard →]"

### Key Features

- **🔍 Proactive Investigation**: Pre-defined RCA scenarios run automatically when anomalies are detected
- **📊 Hybrid Detection**: Statistical baselines + rule-based guardrails (LLMs augment, not replace)
- **🤖 Pluggable AI**: Support for AWS Bedrock, OpenAI, Anthropic, and self-hosted LLMs (Llama, Mistral, etc.)
- **💬 Slack-First Alerts**: Rich notifications with RCA summary, confidence scores, and deep-links to dashboards
- **📈 OpenSearch Dashboards**: Pre-built incident timelines, anomaly views, and evidence explorers
- **🏗️ Infrastructure-as-Code**: Terraform modules with YAML-based detection policies
- **🔐 Privacy-Conscious**: Self-hosted LLM support for airgapped environments
- **☁️ AWS-Native**: Serverless-first architecture with Lambda, Step Functions, OpenSearch, and DynamoDB

---

## 🧑‍💻 Who is this for?

### Platform & SRE Teams
- Deploy and customize the platform for your AWS organization
- Configure detection policies, orchestration rules, and AI provider selection
- Respond to high-signal alerts with pre-investigated root causes
- Maintain visibility across 50+ AWS accounts from a single pane of glass

### Open-Source Contributors
- Extend detection algorithms and add custom integrations
- Improve agentic workflows and RCA scenario coverage
- Share best practices and deployment patterns

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Executive Overview](./docs/1-executive-overview.md) | Vision, scope, tenets, and outcomes |
| [Product Requirements](./docs/2-product-requirements.md) | Functional and non-functional requirements |
| [Product Design](./docs/3-product-design.md) | User journeys, Slack UX, and investigation flow |
| [Technical Architecture](./docs/4-technical-architecture.md) | System architecture, components, and data flow |
| [POC Plan](./docs/5-poc.md) | Scope, scenarios, and success criteria for validation |
| [Guidelines](./docs/6-guidelines.md) | Role-based playbooks and activity runbooks |
| [Terraform Guide](./terraform/README.md) | Infrastructure deployment instructions |
| [Features Roadmap](./FEATURES.md) | Current and planned capabilities |

---

## 🏗️ Repository Structure

```
aiops-platform/
├── README.md                          # This file
├── LICENSE                            # MIT License
├── docs/                              # Documentation
│   ├── 1-executive-overview.md        # Product vision and scope
│   ├── 2-product-requirements.md      # Requirements and constraints
│   ├── 3-product-design.md            # UX and interaction design
│   ├── 4-technical-architecture.md    # Technical architecture and components
│   ├── 5-poc.md                       # Proof-of-concept plan and validation
│   ├── 6-guidelines.md                # Role and activity guideline index
│   ├── guidelines/                    # Role playbooks and activity runbooks
│   ├── components/                    # Component deep dives
│   └── decisions/                     # Architecture decision records (ADRs)
│
├── terraform/                         # Infrastructure-as-Code
│   ├── modules/                       # Reusable Terraform modules
│   │   ├── networking/                # VPC, subnets, security groups
│   │   ├── iam/                       # Cross-account roles, policies
│   │   ├── data-stores/               # S3, OpenSearch, DynamoDB, Timestream
│   │   ├── compute/                   # Lambda functions, Step Functions
│   │   ├── ingestion/                 # Kinesis Firehose, EventBridge
│   │   └── observability/             # CloudWatch alarms, X-Ray
│   │
│   ├── environments/                  # Environment-specific configs
│   │   ├── dev/                       # Development environment
│   │   ├── staging/                   # Staging environment
│   │   └── prod/                      # Production environment
│   │
│   └── member-account/                # Member account setup (cross-account IAM)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── src/                               # Application code
│   ├── ingestion/                     # Log/metric ingestion and normalization
│   │   ├── lambda/                    # Lambda functions
│   │   │   ├── log-normalizer/        # CloudWatch Logs → OpenSearch
│   │   │   └── event-processor/       # EventBridge → DynamoDB
│   │   ├── schemas/                   # Canonical data schemas
│   │   └── tests/
│   │
│   ├── detection/                     # Anomaly detection
│   │   ├── statistical/               # Statistical detection algorithms
│   │   │   ├── baseline.py            # Seasonality baseline (STL)
│   │   │   ├── changepoint.py         # Change-point detection (PELT)
│   │   │   └── scoring.py             # Z-score, EWMA
│   │   ├── rules/                     # Rule-based detectors
│   │   │   ├── error_rate.py
│   │   │   ├── latency.py
│   │   │   └── security.py
│   │   └── tests/
│   │
│   ├── agents/                        # Agentic workflow components
│   │   ├── detection-agent/           # Deduplication, suppression
│   │   ├── correlation-agent/         # Event correlation across accounts
│   │   ├── historical-compare-agent/  # Similarity to past incidents
│   │   ├── rca-agent/                 # Root cause analysis (AI-powered)
│   │   ├── recommendation-agent/      # Runbook mapping
│   │   └── tests/
│   │
│   ├── ai-provider/                   # AI provider abstraction layer
│   │   ├── interface.py               # Abstract base class
│   │   ├── bedrock_provider.py        # AWS Bedrock implementation
│   │   ├── openai_provider.py         # OpenAI API implementation
│   │   ├── anthropic_provider.py      # Anthropic API implementation
│   │   ├── self_hosted_provider.py    # Self-hosted LLM (SageMaker/ECS)
│   │   ├── cost_tracker.py            # Token usage and cost tracking
│   │   └── tests/
│   │
│   ├── alerting/                      # Alert generation and delivery
│   │   ├── slack-notifier/            # Slack Bot (Lambda)
│   │   │   ├── handler.py             # Webhook handler
│   │   │   ├── formatter.py           # Alert payload formatting
│   │   │   └── deeplink.py            # OpenSearch URL generation
│   │   ├── screenshot/                # Dashboard screenshot generator (Phase 1)
│   │   └── tests/
│   │
│   ├── orchestration/                 # Workflow orchestration
│   │   ├── step-functions/            # Step Functions state machines
│   │   │   ├── anomaly-workflow.json  # Main RCA workflow
│   │   │   └── validation.py          # Workflow validation
│   │   └── tests/
│   │
│   └── shared/                        # Shared utilities
│       ├── config.py                  # Configuration loader
│       ├── logger.py                  # Structured logging
│       ├── metrics.py                 # Custom CloudWatch metrics
│       └── dynamodb.py                # DynamoDB helpers
│
├── policies/                          # Detection policy definitions
│   ├── default-policies.yaml          # Default detection policies
│   ├── examples/                      # Example policy configurations
│   │   ├── latency-spike.yaml
│   │   ├── error-rate.yaml
│   │   └── deployment-correlation.yaml
│   └── schemas/                       # Policy JSON schema
│
├── dashboards/                        # OpenSearch dashboard definitions
│   ├── unified-timeline.ndjson        # Incident timeline dashboard
│   ├── anomaly-results.ndjson         # Anomaly detection results
│   ├── rca-evidence-explorer.ndjson   # RCA evidence explorer
│   └── import.sh                      # Dashboard import script
│
├── scripts/                           # Automation scripts
│   ├── setup-member-account.sh        # Configure cross-account ingestion
│   ├── load-policies.sh               # Upload policies to DynamoDB
│   ├── import-opensearch-dashboards.sh # Import pre-built dashboards
│   ├── generate-test-anomaly.sh       # Inject synthetic anomaly for testing
│   └── cost-report.sh                 # Generate AI provider cost report
│
├── tests/                             # Integration and E2E tests
│   ├── integration/                   # Integration tests
│   │   ├── test_ingestion.py
│   │   ├── test_detection.py
│   │   └── test_workflow.py
│   ├── e2e/                           # End-to-end tests
│   │   └── test_anomaly_to_slack.py
│   └── fixtures/                      # Test data
│
└── .github/                           # GitHub Actions workflows (optional)
    └── workflows/
        ├── terraform-plan.yml
        ├── test.yml
        └── deploy.yml
```

---

## 🚀 Quick Start

### Prerequisites

- **AWS Account**: Central observability account + 1+ member accounts
- **Terraform**: v1.5+ ([install guide](https://developer.hashicorp.com/terraform/install))
- **AWS CLI**: Configured with credentials ([install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **Python**: 3.11+ for Lambda functions
- **Slack Workspace**: For alert notifications

### Step 1: Clone the repository

```bash
git clone https://github.com/your-org/aiops-platform.git
cd aiops-platform
```

### Step 2: Configure Terraform variables

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your AWS account IDs, region, Slack webhook, etc.
vim terraform.tfvars
```

### Step 3: Deploy infrastructure

```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy (takes ~15-20 minutes)
terraform apply
```

### Step 4: Configure member accounts

```bash
# For each member account, deploy cross-account IAM role
cd ../../member-account
terraform apply \
  -var="central_account_id=123456789012" \
  -var="account_id=987654321098"
```

### Step 5: Load detection policies

```bash
# Upload default policies
cd ../../../scripts
./load-policies.sh --file ../policies/default-policies.yaml
```

### Step 6: Import OpenSearch dashboards

```bash
./import-opensearch-dashboards.sh \
  --endpoint https://your-opensearch-domain.eu-central-1.es.amazonaws.com
```

### Step 7: Test with synthetic anomaly

```bash
./generate-test-anomaly.sh \
  --service api-gateway \
  --anomaly-type latency-spike
```

You should receive a Slack alert within 2 minutes! 🎉

---

## 🧪 Development

### Local Testing

```bash
# Install dependencies
pip install -r src/requirements.txt

# Run unit tests
pytest tests/

# Run integration tests (requires AWS credentials)
pytest tests/integration/
```

### Building Lambda Functions

```bash
cd src/agents/rca-agent
pip install -r requirements.txt -t package/
cd package && zip -r ../function.zip . && cd ..
zip -g function.zip handler.py
```

### Policy Validation

```bash
# Validate policy syntax
python scripts/validate-policy.py policies/default-policies.yaml
```

---

## 📊 Phased Rollout

### MVP (Current Scope)
✅ Multi-account log/metric/event ingestion  
✅ Hybrid anomaly detection (statistical + rule-based)  
✅ Agentic RCA workflows with Bedrock Claude  
✅ Slack notifications with OpenSearch dashboard links  
✅ 3 pre-built dashboards (timeline, anomalies, evidence)  
✅ IaC-based policy configuration  

### Phase 1 (Planned)
🔲 Screenshot generation for Slack alerts  
🔲 Enhanced cross-account correlation  
🔲 AI provider cost/usage dashboards  
🔲 Detection policy effectiveness metrics  

### Phase 2 (Future)
🔲 Interactive Slack bot (Q&A, acknowledge/snooze)  
🔲 Runbook integration and execution  
🔲 Smart alert routing (per-account channels)  
🔲 Feedback loop for RCA quality improvement  

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](./CONTRIBUTING.md) *(coming soon)* for guidelines.

### Areas for Contribution
- 🧠 **Detection Algorithms**: Add new statistical or ML-based detectors
- 🤖 **RCA Scenarios**: Extend pre-defined investigation patterns
- 🔌 **Integrations**: Add support for new notification channels or AI providers
- 📖 **Documentation**: Improve guides, add examples, translate content
- 🧪 **Testing**: Increase test coverage, add E2E scenarios

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

---

## 🙏 Acknowledgments

Built with ❤️ by Platform/SRE engineers, for Platform/SRE engineers.

Special thanks to the open-source community for:
- [AWS CDK](https://aws.amazon.com/cdk/) and [Terraform](https://www.terraform.io/) for IaC tooling
- [OpenSearch](https://opensearch.org/) for powerful observability dashboards
- [Anthropic Claude](https://www.anthropic.com/) and [Meta Llama](https://llama.meta.com/) for AI capabilities

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/aiops-platform/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/aiops-platform/discussions)
- **Documentation**: [docs/](./docs/)

---

**Built for AWS • Open Source • Production Ready**
