# AIOps Platform (AWS)

## Observe - Engage - Automate

AIOps platform that centralizes AWS signals, applies hybrid anomaly detection, and uses agentic reasoning with pluggable AI providers (including self-hosted open-source LLMs).

**Current scope**: Observe and Engage features (Automate deferred to future phases).

## What it is
- A multi-account, cloud-native observability control plane with centralized data + deterministic orchestration.
- Hybrid detection (statistical, rule-based) with LLM-assisted summarization/correlation, not LLM-first detection.
- Agentic workflow that turns anomalies into RCA, recommendations, and actionable alerts.

## Who it’s for
- **Platform/SRE teams**: implement and customize the platform for their organization; own ingestion, governance, detection policies, orchestration, and cost controls.
- **Service teams**: own service-level signals, deployment metadata, and runbooks; consume alerts, insights, and recommendations.
- **Open-source contributors**: extend detection algorithms, add integrations, improve agentic workflows, and share best practices.

## Tenets
- **AWS-native first**: leverage AWS managed services to minimize operational overhead.
- **Centralize signals, not intelligence**: keep processing near data on AWS.
- **Deterministic first**: LLMs augment explanation/correlation, not replace rule-based detection.
- **Structured outputs**: provide confidence scores and evidence trails; no free-form actions.
- **Pluggable AI**: support commercial APIs (AWS Bedrock, OpenAI, Anthropic) AND self-hosted open-source LLMs (Llama, Mistral, etc.) behind a unified provider interface.
- **Open by default**: modular, extensible architecture that platform teams can adapt to their specific needs.
- **Privacy-conscious**: support airgapped/self-hosted LLM deployments for sensitive environments.

## Core capabilities
### Ingestion (per account → central)
- CloudWatch Logs/Metrics, CloudTrail, VPC Flow Logs, ALB/RDS/EKS/Lambda logs.
- Transport: CloudWatch Logs subscription filters → Kinesis Firehose; EventBridge bus for events; cross-account IAM roles.

### Storage (central observability account)
| Signal         | Storage                                   |
| -------------- | ----------------------------------------- |
| Logs (raw)     | S3 (partitioned by account/service/date)  |
| Logs (indexed) | OpenSearch                                |
| Metrics        | CloudWatch cross-account + Timestream     |
| Events         | EventBridge + DynamoDB                    |
| Traces         | X-Ray / OpenTelemetry (optional)          |

### Normalization & enrichment
- Canonical schema; add account_id, region, service, deployment/version, environment.
- Deduplicate noisy events; aggregate p50/p95/p99; create an “observability feature store” for ML.

### Hybrid anomaly detection
- Statistical/ML: seasonality baselines, change-point detection, z-score/EWMA/STL by service/account.
- Rule-based guardrails: error-rate, latency regression, traffic drops, security events.
- LLM-assisted semantic signals: “new error pattern” / “rare log message”; used for explanation or secondary scoring.
- Output: structured anomaly object (signal, scope, deviation, baseline, confidence, related events).

### Agentic reasoning (deterministic orchestration) - **Engage scope**
- **Detection agent**: consume anomalies, dedupe, suppress noise, decide escalation.
- **Correlation agent**: join infra/app/deploy events across accounts; build causal hints.
- **Historical comparison agent**: last week/deploy/incident similarity.
- **RCA agent** (LLM-flexible): summarizes evidence, proposes probable cause with confidence + links.
- **Recommendation/runbook agent**: maps RCA to known fixes, links to runbooks/documentation/ticketing systems.
- **Interactive chat agent**: natural language Q&A over observability data for on-call engineers.

**Note**: Autonomous remediation (Automate) is explicitly out of scope for initial release; all actions require human approval.

### Orchestration & control plane
- Orchestrator: AWS Step Functions or Temporal; deterministic, replayable, observable, auditable.
- Flow: Anomaly → Correlate → Compare → RCA → Recommend → Alert.
- Policy store for detection thresholds, escalation rules, cost limits, and AI provider selection.

### AI/LLM layer (pluggable & open)
- **Roles**: summarization, semantic clustering, RCA explanation, hypothesis generation, natural language alerting, interactive Q&A.
- **Anti-patterns**: raw log ingestion, real-time gating, acting without confidence, autonomous remediation (out of scope).
- **Provider abstraction**: unified interface supporting:
  - **Commercial APIs**: AWS Bedrock (Claude, Titan, etc.), OpenAI, Anthropic, Azure OpenAI
  - **Self-hosted open-source LLMs**: Llama 3/4, Mistral, Qwen, DeepSeek, etc.
- **Deployment options for self-hosted models**:
  - **SageMaker Real-Time Endpoints**: managed inference with autoscaling, multi-model endpoints, GPU instance support
  - **SageMaker Serverless Inference**: pay-per-use for infrequent usage patterns
  - **EKS with GPU nodes**: full control, node autoscaling, spot instances for cost optimization
  - **ECS/Fargate with Inferentia/Graviton**: AWS-optimized inference chips for cost-effective deployment
- **Multi-tenancy support**: per-account or per-service provider selection; cost allocation tags.
- **Privacy & security**: keep sensitive data in-account with self-hosted models; PII redaction before external API calls; comprehensive prompt/response audit logging.
- **Model registry**: track model versions, performance metrics, and cost per provider; enable A/B testing and gradual rollouts.

### Alerting & UX - **Engage scope**
- **Rich alert payload**: what happened, why we think it happened, what changed, confidence score, what to do next (links to evidence/runbooks/dashboards).
- **Notification channels**: Slack, Microsoft Teams, OpsGenie, PagerDuty, SNS, email.
- **Web UI** (AWS-hosted or self-hosted):
  - Timeline view: unified incident timeline across accounts
  - Chat interface: natural language queries over observability data
  - Evidence explorer: drill into logs/metrics/traces from alerts
  - Feedback loop: thumbs up/down on RCA quality to improve models
- **Extensible integrations**: plugin architecture for custom notification/ticketing systems.

### Security, trust, cost
- Cross-account read-only roles; least privilege.
- Data minimization for prompts; redact sensitive fields; store prompt/decision audit trail.
- Human-in-the-loop for actions; cost caps per account/service; budget alarms on LLM usage.

## Deployment footprint (AWS-native)
### Data plane (Observe)
- **Ingestion**: CloudWatch Logs subscription filters, Kinesis Data Firehose, EventBridge, CloudTrail
- **Storage**: S3 (raw logs, partitioned), OpenSearch Serverless (indexed logs), Timestream (metrics), DynamoDB (events/metadata)
- **Optional**: X-Ray or OpenTelemetry Collector for distributed tracing

### Compute & processing
- **Normalization/enrichment**: Lambda (event-driven) or Fargate (streaming)
- **Anomaly detection**: SageMaker (statistical/ML models) or Lambda (rule-based)
- **Agentic workflows**: Step Functions (serverless orchestration) or ECS/Fargate (long-running agents)

### Control plane (Engage)
- **API layer**: API Gateway + Lambda or Application Load Balancer + ECS
- **State management**: DynamoDB (policy store, agent state, audit logs)
- **Orchestration**: Step Functions for workflow coordination

### AI/LLM infrastructure
- **Commercial**: AWS Bedrock (managed, multi-model), API clients for OpenAI/Anthropic
- **Self-hosted open-source**:
  - SageMaker endpoints (real-time or serverless) with autoscaling
  - EKS cluster with GPU node groups (g5/p4 instances) + Karpenter for autoscaling
  - ECS/Fargate with Inferentia2 instances for cost-optimized inference
  - Model artifacts stored in S3; served via TorchServe, vLLM, or TensorRT-LLM
- **Model management**: SageMaker Model Registry or custom metadata store

### Infrastructure as Code
- **Deployment**: AWS CDK or Terraform modules for reproducible deployments
- **Configuration**: Systems Manager Parameter Store or AppConfig for runtime settings
- **Secrets**: AWS Secrets Manager for API keys, cross-account role ARNs

## Phasing & roadmap
### Phase 1: Observe + Engage (current scope)
- ✅ Multi-account log/metric/event ingestion
- ✅ Hybrid anomaly detection (statistical + rule-based)
- ✅ Agentic RCA and recommendations (with human-in-the-loop)
- ✅ Pluggable AI providers (commercial + self-hosted open-source LLMs)
- ✅ Rich alerting and interactive chat UI
- ✅ Open-source release with modular architecture

### Phase 2: Automate (future)
- 🔲 Autonomous remediation workflows (rollback, scale, config changes)
- 🔲 Change management integration (approval workflows, blast radius limits)
- 🔲 Closed-loop feedback (measure remediation effectiveness)
- 🔲 Progressive automation (shadow mode → assisted → autonomous)

## Non-goals (for Phase 1)
- **Autonomous remediation**: all actions require explicit human approval.
- **On-prem deployment**: AWS-native architecture; hybrid-cloud support deferred.
- **Deep APM features**: basic trace ingestion only; not replacing full APM solutions.
- **Real-time log search at petabyte scale**: optimized for recent data + alerts, not ad-hoc historical queries.

## Open-source strategy
- **License**: Apache 2.0 or MIT for maximum adoption.
- **Repository structure**: modular components (ingestion, detection, agents, UI) for selective adoption.
- **Documentation**: architecture diagrams, deployment guides, customization examples, API references.
- **Community**: contribution guidelines, issue templates, discussion forums.
- **Reference implementations**: sample deployments for common AWS architectures (EKS-heavy, serverless-first, multi-region).
- **Extensibility points**: plugin interfaces for custom detectors, notification channels, and AI providers.
