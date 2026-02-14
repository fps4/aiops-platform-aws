# Requirements & UX

## Overview
The AIOps Platform provides **proactive anomaly detection with AI-assisted RCA** for Platform/SRE teams managing multi-account AWS environments. The system autonomously investigates common failure scenarios and presents findings via Slack notifications with deep-links to OpenSearch dashboards for detailed analysis.

**Philosophy**: Investigate first, alert with answers—not questions.

---

## User Personas

### Platform/SRE Teams (Primary Users)
**Role**: Own and operate the AIOps platform; respond to alerts and investigate incidents.

**Responsibilities**:
- Configure detection policies and orchestration rules via Infrastructure-as-Code
- Respond to proactive anomaly alerts in Slack
- Investigate root causes using OpenSearch dashboards
- Manage AI provider selection per agent type
- Monitor platform cost and effectiveness

**Pain Points**:
- Alert fatigue from noisy monitoring systems
- Time wasted on manual correlation across accounts/services
- Delayed incident response due to lack of context
- Difficulty identifying root cause in distributed systems

**Goals**:
- Receive high-signal alerts with probable root cause already identified
- Quickly drill into evidence via pre-built dashboards
- Minimize MTTR (Mean Time To Resolution)
- Maintain visibility across all AWS accounts from a single pane of glass

---

## Core User Workflows

### 1. Proactive Anomaly Detection & Investigation (Autonomous)
**Trigger**: Statistical anomaly, rule violation, or semantic log pattern detected.

**Agent Workflow** (automated, before user sees alert):
1. **Detection Agent**: Identifies anomaly, deduplicates, applies suppression rules
2. **Correlation Agent**: Joins related infra/app/deployment events across accounts
3. **Historical Comparison Agent**: Checks similarity to past incidents/deployments
4. **RCA Agent**: Investigates pre-defined common scenarios:
   - Recent deployment correlation (code/config change caused issue)
   - Infrastructure change impact (autoscaling, instance failures)
   - Dependency failure propagation (downstream service degradation)
   - Resource exhaustion patterns (OOM, throttling, disk space)
   - Security/access issues (IAM, network policy changes)
5. **Recommendation Agent**: Maps probable cause to known fixes/runbooks

**Output**: Structured alert with RCA, confidence score, and evidence links—delivered to Slack.

---

### 2. Receiving & Reviewing Alerts (Slack)
**Actor**: Platform/SRE engineer on-call or monitoring shared channel.

**Flow**:
1. **Notification arrives** in single shared Slack channel (#aiops-alerts)
2. **Alert payload includes**:
   - **What happened**: "Latency spike on api-gateway service in prod-account-123"
   - **Probable root cause**: "Deployment v2.3.1 at 09:15 UTC introduced 500ms+ DB query"
   - **Confidence**: "High (85%)" or "Medium (60%)" with reasoning
   - **Link**: Direct URL to OpenSearch dashboard filtered to relevant timeframe/service
   - **Screenshot** (optional): Embedded visualization of the anomaly
3. **Engineer reviews** summary in Slack, clicks link to OpenSearch for deeper investigation

**Success Criteria**:
- Engineer understands issue severity and probable cause within 30 seconds
- No need to manually correlate logs, metrics, or deployment events
- Single click to detailed evidence

---

### 3. Investigating Evidence (OpenSearch Dashboards)
**Actor**: Platform/SRE engineer investigating alert or exploring anomalies.

**Dashboard Types** (pre-built):
1. **Unified Incident Timeline**:
   - Time-series view across all accounts, showing anomalies, deployments, infra changes
   - Filterable by account, region, service, severity
   - Drill-down to specific incident details
2. **Anomaly Detection Results**:
   - Detected anomalies with baselines, deviation magnitude, confidence scores
   - Visualizations: error rate trends, latency histograms, traffic patterns
   - Comparison views: current vs baseline, today vs last week
3. **RCA Evidence Explorer**:
   - Correlated logs, metrics, events, traces for a specific incident
   - Side-by-side comparison: pre-incident vs during-incident state
   - Event timeline: deployments, autoscaling actions, config changes

**Navigation Flow**:
- Click Slack alert link → lands on pre-filtered dashboard showing relevant timeframe/scope
- Use OpenSearch native features (Discover, Visualize, Dashboard) to explore further
- Export findings or share dashboard links with team

**Success Criteria**:
- Zero manual filter configuration on dashboard load (pre-filtered via alert link)
- All relevant signals (logs, metrics, events) co-located in single view
- Evidence trail supports or refutes AI-generated RCA hypothesis

---

### 4. Configuring Detection Policies (Infrastructure-as-Code)
**Actor**: Platform/SRE team implementing or tuning detection policies.

**Configuration Method** (MVP):
- **Primary**: Terraform modules with JSON/YAML policy files
- **Fallback**: REST API for dynamic updates (e.g., emergency threshold changes)

**Policy Definition** (example structure):
```yaml
detection_policies:
  - name: api-latency-spike
    scope:
      accounts: ["prod-*"]
      services: ["api-gateway", "user-service"]
    detection:
      type: statistical
      metric: p95_latency_ms
      baseline_window: 7d
      sensitivity: high  # low, medium, high
      threshold:
        z_score: 3.0
        min_deviation_pct: 50
    actions:
      alert: true
      run_rca: true
      agent_provider: bedrock-claude-sonnet  # per-agent override
      suppress_similar_minutes: 30
```

**Workflow**:
1. Engineer defines or updates policy YAML in Git repository
2. Terraform apply pushes policy to DynamoDB policy store
3. Detection agents reload policies (via EventBridge notification)
4. Changes take effect within 1-2 minutes

**Success Criteria**:
- Policy changes are version-controlled, reviewable, auditable
- No custom UI required for policy management (IaC-native)
- Supports account/service scoping, per-agent AI provider selection

---

## Phased Feature Rollout

### MVP (Minimum Viable Product)
**Goal**: Prove value with proactive RCA alerts and basic investigation tools.

**Included**:
- ✅ Proactive anomaly detection (statistical + rule-based)
- ✅ Automated RCA investigation for common scenarios
- ✅ Slack notifications with RCA summary + OpenSearch link
- ✅ 3 core OpenSearch dashboards (timeline, anomalies, evidence)
- ✅ Single shared Slack channel (#aiops-alerts)
- ✅ IaC-based policy configuration (Terraform + YAML)
- ✅ Per-agent-type AI provider selection
- ✅ 90-day retention default (configurable)

**Deferred to Phase 1**:
- Screenshot generation for Slack notifications (nice-to-have)

### Phase 1 (Enhanced Observability)
**Goal**: Improve signal-to-noise ratio and add operational context.

**Additions**:
- 🔲 Screenshot generation for OpenSearch dashboards in Slack alerts
- 🔲 Enhanced correlation across accounts (deployment metadata enrichment)
- 🔲 Cost/usage observability for AI provider consumption
- 🔲 Detection policy effectiveness dashboard

### Phase 2 (Interactive Engagement)
**Goal**: Enable engineers to take action directly from Slack and customize alert routing.

**Additions**:
- 🔲 Interactive Slack actions: acknowledge, snooze, escalate alerts
- 🔲 Slack bot Q&A: "show me errors for service-x", "why did latency spike?"
- 🔲 Runbook integration: recommended actions with execution links
- 🔲 Smart alert routing: per-account/severity channels, on-call tagging
- 🔲 Feedback loop: 👍/👎 reactions to improve RCA quality
- 🔲 Thread-based detailed evidence in Slack (avoid dashboard navigation for simple cases)

---

## Non-Functional Requirements

### Performance
- **Alert latency**: Anomaly detection → Slack notification < 2 minutes (P95)
- **RCA generation**: Initial findings within 60 seconds, full analysis within 5 minutes
- **Dashboard load time**: Pre-filtered OpenSearch dashboards load < 3 seconds
- **Screenshot generation**: < 10 seconds (when implemented in Phase 1)

### Reliability
- **Alert delivery**: 99.9% delivery success rate (Slack API retries + dead-letter queue)
- **Data ingestion**: No data loss for logs/metrics (S3 durability, Kinesis retries)
- **Agent resilience**: Workflow retries on transient failures (Step Functions built-in)

### Scalability
- **Multi-account**: Support 50+ AWS accounts in MVP (horizontally scalable to 500+)
- **Anomaly throughput**: Process 10,000 metrics/minute per account
- **Alert volume**: Handle 100+ concurrent incidents without degradation

### Security & Privacy
- **Data isolation**: Cross-account read-only IAM roles with least privilege
- **Audit trail**: All AI provider calls logged (prompts, responses, metadata) to S3
- **PII redaction**: Remove sensitive fields before LLM prompts (optional for self-hosted models)
- **Access control**: Platform admins only; OpenSearch dashboards authenticated via IAM

### Cost Control
- **AI provider limits**: Per-agent cost caps (e.g., $100/day/agent type)
- **Data retention**: Default 90 days (configurable), automated lifecycle policies
- **Compute efficiency**: Serverless-first architecture (Lambda, Step Functions, Fargate Spot)

---

## Success Metrics

### User Satisfaction
- **MTTR reduction**: 50% faster incident resolution vs manual investigation
- **Alert noise**: <5% false positive rate (measured by feedback loop in Phase 2)
- **Adoption**: 80%+ of on-call engineers use platform within 3 months

### System Performance
- **RCA accuracy**: 70%+ correct root cause identification (validated by engineer feedback)
- **Confidence calibration**: High-confidence alerts (>80%) have >85% accuracy
- **Coverage**: Detect 90%+ of P0/P1 incidents before manual escalation

### Operational Efficiency
- **Cost per alert**: <$0.50 per fully-investigated anomaly (including AI provider costs)
- **Time saved**: 30 minutes average saved per incident vs manual RCA
- **Alert volume**: 10-50 high-quality alerts per day across 50 accounts (not thousands)

---

## Out of Scope (for Phases 1 & 2)

### Autonomous Remediation (Phase 3+)
- Automatic rollbacks, scaling actions, or configuration changes
- Requires separate approval workflows, blast radius controls, closed-loop validation

### Multi-Cloud Support
- AWS-native architecture; GCP/Azure integration deferred to future phases

### Real-Time Log Search at Petabyte Scale
- OpenSearch optimized for recent data (90 days); not replacing enterprise log archival

### Deep APM Features
- Basic trace ingestion only; not replacing Datadog/New Relic/Dynatrace

