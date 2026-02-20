# Feature Roadmap

This document tracks features being built now, planned for upcoming phases, and under consideration for future releases.

**Legend**:
- ✅ **Implemented** - Feature is complete and available
- 🚧 **In Progress** - Currently under active development
- 📋 **Planned** - Committed for upcoming phase
- 💡 **Proposed** - Under consideration, not yet committed

---

## MVP (Current Development)

Building the foundation for proactive anomaly detection and RCA.

### Data Ingestion & Storage
| Feature | Status | Description |
|---------|--------|-------------|
| Multi-Account CloudWatch Logs Ingestion | 🚧 | Ingest logs from 50+ AWS accounts via Kinesis Firehose |
| CloudWatch Metrics Cross-Account | 🚧 | Read metrics from member accounts using cross-account IAM |
| CloudTrail Event Ingestion | 🚧 | Capture API activity, IAM changes, config modifications via CloudWatch Logs pipeline |
| S3 Raw Log Storage | 🚧 | Partitioned by account/service/date with lifecycle policies |
| OpenSearch Serverless Indexing | 🚧 | Index normalized logs and metrics for search, visualization, and time-series aggregations |
| DynamoDB Event Store | 🚧 | Store deployment events, anomalies, agent state |

### Anomaly Detection
| Feature | Status | Description |
|---------|--------|-------------|
| Statistical Baseline Detection | 🚧 | STL decomposition for seasonality patterns (Fargate scheduled task) |
| Change-Point Detection | 🚧 | PELT algorithm to detect sudden metric shifts (Fargate scheduled task) |
| Z-Score Anomaly Scoring | 🚧 | Standard deviation-based scoring with sliding windows (Fargate scheduled task) |
| EWMA Anomaly Scoring | 🚧 | Exponentially weighted moving average for trend detection (Fargate scheduled task) |
| Rule-Based Error Rate Alerts | 🚧 | Threshold-based alerts for error rates >5% |
| Rule-Based Latency Regression | 🚧 | Detect latency >2x baseline for 3+ minutes |
| Rule-Based Traffic Drop Detection | 🚧 | Alert on >80% traffic drop (canary failure detection) |
| Security Event Detection | 🚧 | IAM policy changes, S3 public access modifications |
| Configurable Sensitivity Levels | 🚧 | Low/medium/high sensitivity (4σ/3σ/2σ) per policy |

### Agentic Workflows
| Feature | Status | Description |
|---------|--------|-------------|
| Detection Agent | 🚧 | Deduplicate and suppress noisy anomalies |
| Correlation Agent | 🚧 | Join infra/app/deployment events across accounts |
| Historical Comparison Agent | 🚧 | Find similar past incidents and deployments |
| RCA Agent - Deployment Correlation | 🚧 | Investigate deployment-related issues |
| RCA Agent - Infrastructure Changes | 🚧 | Analyze autoscaling, instance failures, AZ issues |
| RCA Agent - Dependency Failures | 🚧 | Detect downstream service impact propagation |
| RCA Agent - Resource Exhaustion | 🚧 | Identify OOM, throttling, disk space issues |
| RCA Agent - Security/Access Issues | 🚧 | Analyze IAM, security group, network ACL changes |
| Recommendation Agent | 🚧 | Map probable cause to known fixes and runbooks |
| Orchestrator Lambda | 🚧 | Single Lambda triggered by DynamoDB Stream, runs full agent pipeline sequentially |

### AI Provider Integration
| Feature | Status | Description |
|---------|--------|-------------|
| AI Provider Abstraction Layer | 🚧 | Unified interface for multiple AI providers |
| AWS Bedrock Integration (Claude) | 🚧 | Claude Sonnet/Haiku for RCA and summarization |
| Per-Agent-Type Provider Selection | 🚧 | Configure different models per agent (RCA, correlation, etc.) |
| Cost Tracking & Limits | 🚧 | Per-agent daily cost caps with CloudWatch alarms |
| Prompt/Response Audit Logging | 🚧 | Log all AI calls to S3 for compliance and debugging |
| Token Usage Metrics | 🚧 | Track input/output tokens and cost per invocation |

### Alerting & Dashboards
| Feature | Status | Description |
|---------|--------|-------------|
| Slack Webhook Integration | 🚧 | Post rich alerts to #aiops-alerts channel |
| Slack Alert Formatting (Block Kit) | 🚧 | Structured alerts with RCA summary and confidence |
| OpenSearch Dashboard Deep-Links | 🚧 | Pre-filtered dashboard URLs in Slack notifications |
| Unified Incident Timeline Dashboard | 🚧 | Anomalies, deployments, events across all accounts |
| Anomaly Detection Results Dashboard | 🚧 | Metrics vs baselines, deviation heatmaps |
| RCA Evidence Explorer Dashboard | 🚧 | Correlated logs, metrics, events for incident investigation |
| IAM-Authenticated Dashboard Access | 🚧 | Secure access to OpenSearch Dashboards |

### Infrastructure & Operations
| Feature | Status | Description |
|---------|--------|-------------|
| Terraform Modular Architecture | 🚧 | Reusable modules for networking, IAM, data stores, compute |
| Single-Region Deployment (eu-central-1) | 🚧 | MVP deployed to single region for simplicity |
| Fargate Scheduled Detection Task | 🚧 | ECS Fargate task for statistical detection, triggered every 5 min via EventBridge Scheduler |
| Lambda-Based Slack Bot | 🚧 | Serverless webhook handler for notifications |
| Cross-Account IAM Roles | 🚧 | Least-privilege read-only roles for member accounts |
| DynamoDB Policy Store | 🚧 | Store detection policies loaded from YAML files |
| IaC-Based Policy Configuration | 🚧 | Terraform + YAML for detection policy management |
| 90-Day Default Retention | 🚧 | Configurable retention for logs, metrics, anomalies |
| CloudWatch Alarms & Monitoring | 🚧 | Pipeline health, data lag, cost alerts |

---

## Phase 1 (Next 3-4 Months)

Enhance observability and operational insights.

### Alerting Enhancements
| Feature | Status | Description |
|---------|--------|-------------|
| Dashboard Screenshot Generation | 📋 | Embed OpenSearch dashboard screenshots in Slack alerts |
| Headless Browser Service | 📋 | Puppeteer/Playwright Lambda for screenshot capture |
| Screenshot S3 Storage | 📋 | Store screenshots with 24-hour expiry |

### Observability & Metrics
| Feature | Status | Description |
|---------|--------|-------------|
| AI Provider Cost Dashboard | 📋 | OpenSearch dashboard for per-agent cost/usage tracking |
| Detection Policy Effectiveness Metrics | 📋 | Track true positives, false positives, accuracy per policy |
| Multi-Account Deployment Metadata | 📋 | Enhanced correlation with deployment version tracking |
| Enriched Log Normalization | 📋 | Add environment tags, service ownership metadata |

### AI Provider Expansion
| Feature | Status | Description |
|---------|--------|-------------|
| OpenAI API Integration | 📋 | Support for GPT-4/GPT-5 models |
| Anthropic Direct API Integration | 📋 | Direct Claude API (non-Bedrock) |
| Self-Hosted LLM via SageMaker | 📋 | Deploy Llama/Mistral on SageMaker endpoints |
| Model Performance Comparison | 📋 | A/B testing framework for RCA quality |

---

## Phase 2 (6-12 Months)

Enable interactive engagement and feedback loops.

### Interactive Slack Features
| Feature | Status | Description |
|---------|--------|-------------|
| Slack Bot Natural Language Q&A | 📋 | Ask questions like "show me errors for service-x" |
| Acknowledge/Snooze Alerts (Slack Buttons) | 📋 | Inline alert management without leaving Slack |
| Escalate Alerts (Slack Actions) | 📋 | Escalate to PagerDuty or on-call rotation |
| Request Deeper RCA (Slack Command) | 📋 | Trigger additional investigation on demand |
| Threaded Detailed Evidence | 📋 | Post evidence details in Slack threads |

### Alert Routing & Notification
| Feature | Status | Description |
|---------|--------|-------------|
| Smart Alert Routing | 📋 | Route to different Slack channels by account/severity |
| Per-Account Alert Channels | 📋 | Configure custom channels per AWS account |
| On-Call Engineer Tagging | 📋 | Auto-mention on-call engineers in alerts |
| Microsoft Teams Integration | 📋 | Support Teams as alternative to Slack |
| PagerDuty Integration | 📋 | Auto-create incidents for P0/P1 anomalies |
| OpsGenie Integration | 📋 | Escalation and on-call management |

### Runbook Integration
| Feature | Status | Description |
|---------|--------|-------------|
| Runbook Mapping | 📋 | Link RCA results to known runbooks/playbooks |
| Runbook Execution Triggers | 📋 | One-click runbook execution from Slack |
| Runbook Effectiveness Tracking | 📋 | Measure resolution time by runbook |

### Feedback & Quality Improvement
| Feature | Status | Description |
|---------|--------|-------------|
| RCA Quality Feedback (👍/👎) | 📋 | Collect engineer feedback on RCA accuracy |
| Feedback-Based Model Retraining | 📋 | Use feedback to improve detection/RCA models |
| Confidence Score Calibration | 📋 | Adjust confidence thresholds based on accuracy |
| False Positive Suppression Learning | 📋 | Auto-suppress repeated false positives |

---

## Phase 3+ (Future / Under Consideration)

Long-term vision and advanced capabilities.

### Autonomous Remediation
| Feature | Status | Description |
|---------|--------|-------------|
| Automated Rollback Workflows | 💡 | Auto-rollback deployments on critical anomalies |
| Auto-Scaling Adjustments | 💡 | Trigger scaling actions based on resource exhaustion |
| Configuration Auto-Remediation | 💡 | Fix known config issues (IAM, security groups) |
| Change Management Integration | 💡 | Approval workflows with blast radius limits |
| Closed-Loop Feedback | 💡 | Measure remediation effectiveness, rollback if needed |
| Progressive Automation | 💡 | Shadow mode → assisted → autonomous |

### Multi-Cloud & Hybrid Support
| Feature | Status | Description |
|---------|--------|-------------|
| GCP Integration | 💡 | Ingest logs/metrics from Google Cloud Platform |
| Azure Integration | 💡 | Ingest logs/metrics from Microsoft Azure |
| On-Premises Support | 💡 | Ingest from self-hosted infrastructure |
| Multi-Cloud Correlation | 💡 | Cross-cloud incident correlation |

### Advanced Detection & ML
| Feature | Status | Description |
|---------|--------|-------------|
| Deep Learning Anomaly Detection | 💡 | LSTM/Transformer models for complex patterns |
| Reinforcement Learning for Policy Tuning | 💡 | Auto-tune detection policies based on feedback |
| Anomaly Clustering | 💡 | Group related anomalies into incidents |
| Predictive Anomaly Detection | 💡 | Forecast anomalies before they occur |
| Seasonal Pattern Learning | 💡 | Auto-detect weekly/monthly patterns |

### Enhanced Observability
| Feature | Status | Description |
|---------|--------|-------------|
| Distributed Tracing Deep Integration | 💡 | X-Ray/OpenTelemetry trace analysis in RCA |
| Cost Attribution by Service/Team | 💡 | Chargeback for AI provider usage |
| Real-Time Log Search (Petabyte Scale) | 💡 | Sub-second queries over years of logs |
| Multi-Region Active-Active Deployment | 💡 | High-availability control plane |
| Disaster Recovery Automation | 💡 | Cross-region failover and data replication |

### Advanced Integrations
| Feature | Status | Description |
|---------|--------|-------------|
| Jira Ticketing Integration | 💡 | Auto-create tickets for unresolved incidents |
| ServiceNow Integration | 💡 | ITSM workflow integration |
| Datadog/New Relic APM Integration | 💡 | Ingest APM traces and metrics |
| GitHub Actions Integration | 💡 | Trigger workflows on deployment anomalies |
| Custom Webhook Plugins | 💡 | Extensible plugin system for any integration |

### User Experience
| Feature | Status | Description |
|---------|--------|-------------|
| Custom Web UI (Optional) | 💡 | Standalone web app as OpenSearch alternative |
| Mobile App Notifications | 💡 | iOS/Android push notifications for critical alerts |
| Voice Assistant Integration | 💡 | Ask Alexa/Google Assistant about incidents |
| Customizable Alert Templates | 💡 | Per-team alert formatting preferences |

---

## Feature Request Process

Have an idea for a new feature? We'd love to hear it!

1. **Check existing issues**: Search [GitHub Issues](https://github.com/your-org/aiops-platform/issues) to avoid duplicates
2. **Create a feature request**: Use the "Feature Request" issue template
3. **Provide context**: Describe the problem you're solving and why it matters
4. **Discuss with community**: Engage in [GitHub Discussions](https://github.com/your-org/aiops-platform/discussions)
5. **Contribute**: Consider implementing the feature yourself! See [CONTRIBUTING.md](./CONTRIBUTING.md)

---

## Phase Decision Criteria

Features are prioritized based on:

1. **User Impact**: How many users benefit? How much time/pain does it save?
2. **Complexity**: Engineering effort required (MVP = simple, Phase 2+ = complex)
3. **Dependencies**: Does it require other features to be built first?
4. **Community Demand**: How many users are requesting it?
5. **Strategic Alignment**: Does it align with core platform vision?

**MVP Focus**: Prove core value (proactive RCA) with minimal complexity.  
**Phase 1 Focus**: Production-readiness and operational insights.  
**Phase 2 Focus**: Interactivity and quality feedback loops.  
**Phase 3+ Focus**: Autonomous actions and advanced intelligence.

---

## Contributing to Features

Want to accelerate a feature or propose something new?

- 💬 **Discuss**: Join [GitHub Discussions](https://github.com/your-org/aiops-platform/discussions) to shape the roadmap
- 🐛 **File Issues**: Report bugs or request enhancements via [GitHub Issues](https://github.com/your-org/aiops-platform/issues)
- 🛠️ **Submit PRs**: Implement features yourself! See development guide in [README.md](./README.md)
- 📖 **Improve Docs**: Help document existing features or write guides

---

**Last Updated**: 2026-02-14  
**Current Phase**: MVP (In Progress)  
**Next Milestone**: MVP Release (Week 8)
