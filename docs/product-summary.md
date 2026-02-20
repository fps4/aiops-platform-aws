# AIOps Platform (AWS)

## Observe - Engage - Automate

Agentic AIOps platform that centralizes AWS signals, applies hybrid anomaly detection, and uses agentic reasoning with pluggable AI providers (including self-hosted open-source LLMs).

**Current scope**: Observe and Engage features (Automate deferred to future phases).

## What it is
- A multi-account, cloud-native observability control plane with centralized data and deterministic orchestration.
- Hybrid detection (statistical, rule-based) with LLM-assisted summarization/correlation, not LLM-first detection.
- Agentic workflow that turns anomalies into RCA, recommendations, and actionable alerts.

## Who it's for
- **Platform/SRE teams**: implement and customize the platform for their organization; own ingestion, governance, detection policies, orchestration, and cost controls; consume alerts, insights, and recommendations.
- **Open-source contributors**: extend detection algorithms, add integrations, improve agentic workflows, and share best practices.

## Tenets
- **AWS-native first**: leverage AWS managed services to minimize operational overhead.
- **Centralize signals, not intelligence**: keep processing near data on AWS.
- **Deterministic first**: LLMs augment explanation/correlation, not replace rule-based detection.
- **Structured outputs**: provide confidence scores and evidence trails; no free-form actions.
- **Pluggable AI**: support commercial and self-hosted open-source LLMs behind a unified provider interface.
- **Open by default**: modular, extensible architecture that platform teams can adapt to their specific needs.
- **Privacy-conscious**: support airgapped/self-hosted LLM deployments for sensitive environments.

## Core capabilities

### Multi-account signal ingestion
- Collect logs, metrics, and API activity from multiple AWS accounts into a central observability account.
- Supported sources: application logs, infrastructure metrics, API audit trails, load balancer and database logs.
- Automatic normalization to a canonical schema with account, region, service, environment, and deployment metadata.
- Deduplication of noisy events; aggregation of key percentiles (p50/p95/p99).

### Hybrid anomaly detection
- **Statistical detection**: seasonality baselines (STL decomposition), change-point detection (PELT), z-score/EWMA scoring per service and account.
- **Rule-based guardrails**: hard thresholds for error rates, latency regressions, traffic drops, and security events.
- **LLM-assisted semantic signals**: detect new error patterns and rare log messages; used for explanation or secondary scoring.
- **Output**: structured anomaly objects with signal, scope, deviation, baseline, confidence, and related events.
- **Configurable policies**: per-service sensitivity, baseline windows, cooldown periods, and suppression rules.

### Agentic reasoning (Engage)
- **Detection agent**: consume anomalies, deduplicate, apply suppression rules, decide escalation.
- **Correlation agent**: join infrastructure, application, and deployment events across accounts; build causal hints.
- **Historical comparison agent**: find similar past incidents, compare to last deployment or last week.
- **RCA agent**: summarize evidence, propose probable root cause with confidence scores and supporting links.
- **Recommendation/runbook agent**: map root cause to known fixes, link to runbooks and documentation.
- **Interactive chat agent**: natural language Q&A over observability data for on-call engineers.

All actions require human approval — autonomous remediation is out of scope for Phase 1.

### Deterministic orchestration
- Replayable, auditable, and observable workflow pipeline.
- Flow: Anomaly → Correlate → Compare → RCA → Recommend → Alert.
- Policy store for detection thresholds, escalation rules, cost limits, and AI provider selection.

### Pluggable AI providers
- **Unified provider interface** supporting per-agent model selection.
- **Commercial APIs**: AWS Bedrock, OpenAI, Anthropic.
- **Self-hosted open-source LLMs**: Llama, Mistral, Qwen, DeepSeek, and others.
- **AI roles**: summarization, semantic clustering, RCA explanation, hypothesis generation, natural language alerting.
- **Anti-patterns**: raw log ingestion, real-time gating, acting without confidence.
- **Cost controls**: per-agent cost caps, budget alarms, cost allocation per account/service.
- **Privacy**: keep sensitive data in-account with self-hosted models; PII redaction before external API calls; full prompt/response audit trail.

### Alerting & UX (Engage)
- **Rich alert payload**: what happened, why it happened, what changed, confidence score, and recommended next steps.
- **Primary interface**: Slack notifications with interactive chat and natural language queries.
- **Dashboards**: unified incident timeline, anomaly detection results, and RCA evidence explorer with drill-down into logs and metrics.
- **Deep-linking**: alerts link directly to pre-filtered dashboards for the affected service and timeframe.
- **Feedback loop**: reactions on RCA quality to improve models over time.
- **Additional channels**: Microsoft Teams, OpsGenie, PagerDuty, SNS, email.
- **Extensible**: plugin architecture for custom notification and ticketing integrations.

### Security, trust, cost
- Cross-account read-only roles with least privilege.
- Data minimization for AI prompts; redact sensitive fields; store prompt/decision audit trail.
- Human-in-the-loop for all actions; cost caps per account/service; budget alarms on AI usage.

## Phasing & roadmap

### Phase 1: Observe + Engage (current scope)
- Multi-account log/metric/event ingestion
- Hybrid anomaly detection (statistical + rule-based)
- Agentic RCA and recommendations (with human-in-the-loop)
- Pluggable AI providers (commercial + self-hosted open-source LLMs)
- Rich Slack notifications with interactive chat and dashboard integration
- Open-source release with modular architecture

### Phase 2: Automate (future)
- Autonomous remediation workflows (rollback, scale, config changes)
- Change management integration (approval workflows, blast radius limits)
- Closed-loop feedback (measure remediation effectiveness)
- Progressive automation (shadow mode → assisted → autonomous)

## Non-goals (Phase 1)
- **Autonomous remediation**: all actions require explicit human approval.
- **On-prem deployment**: AWS-native architecture; hybrid-cloud support deferred.
- **Deep APM features**: basic trace ingestion only; not replacing full APM solutions.
- **Real-time log search at petabyte scale**: optimized for recent data and alerts, not ad-hoc historical queries.

## Open-source strategy
- **License**: MIT for maximum adoption.
- **Repository structure**: modular components (ingestion, detection, agents, UI) for selective adoption.
- **Documentation**: architecture diagrams, deployment guides, customization examples, API references.
- **Community**: contribution guidelines, issue templates, discussion forums.
- **Reference implementations**: sample deployments for common AWS architectures.
- **Extensibility points**: plugin interfaces for custom detectors, notification channels, and AI providers.
