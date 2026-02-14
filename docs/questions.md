# Questions for UX Requirements & Solution Design

Please answer the following questions to help define the UX requirements and solution design for the AIOps Platform.

**Note**: Platform users are **Platform/SRE teams**. Dashboards use **AWS OpenSearch UI**, notifications and chat use **Slack**.

---

## **User Workflows**

### 1. Primary user journeys
What are the primary workflows for Platform/SRE teams?
- Receiving and responding to alerts in Slack
- Investigating anomalies in OpenSearch dashboards
- Configuring detection policies and orchestration rules
- Reviewing RCA quality and providing feedback
- Managing AI provider selection and cost controls

**Answer:**


### 2. Slack chat capabilities
What types of natural language questions should the Slack bot handle? Examples:
- "show me errors for service-x in last hour"
- "why did latency spike at 9am?"
- "compare today's deployment to last week"
- "what's the status of incident-123?"
- "summarize anomalies across all accounts today"

**Answer:**
I was considering a pre-defined scenarios (most commonly used questions) that AI agent in the background is investigating from the beginning and coming already with findings instead of an engineer starts asking quesitons. Most probably cause for example is the search criteria. The trigger is either anomaly or errors or anything else from the common use-cases of AIops agents. Any further clarifications needed?


### 3. Detection policy configuration
How should Platform/SRE teams **configure detection policies**? 
- Infrastructure-as-Code (Terraform with JSON/YAML config files)
- API calls (REST/GraphQL)
- OpenSearch Dashboards plugin/UI (if custom UI needed)
- Combination of above?

**Answer:**
Ideally Infrastructure-as-Code (Terraform with JSON/YAML config files)
where not feasible API calls.

---

## **Slack Notification Design**

### 4. Notification payload structure
For Slack notifications, what information should be included in the MVP?
- RCA summary (what/why/confidence)
- Link to OpenSearch dashboard
- Screenshot of key visualization
- Recommended actions / runbook links
- Inline buttons (acknowledge, snooze, escalate)
- Thread with detailed evidence

**Answer:**
- RCA summary (what/why/confidence)
- Link to OpenSearch dashboard
- Screenshot of key visualization

the rest pu in phase 2

### 5. Interactive Slack actions
Should users be able to respond inline in Slack (via buttons/slash commands)?
- Acknowledge/snooze alerts
- Request deeper RCA
- Trigger runbooks
- Ask follow-up questions to the chat agent
- Provide feedback (👍/👎) on RCA quality

**Answer:**
all phase 2

### 6. Alert routing and channels
How should alerts be routed?
- Single shared Slack channel for all alerts
- Different channels per account/region/service
- Smart routing based on alert severity/type
- User mentions/tagging for on-call rotation

**Answer:**
phase 1: - Single shared Slack channel for all alerts

---

## **OpenSearch Dashboard Integration**

### 7. Dashboard types needed
What OpenSearch dashboards should be pre-built?
- Unified incident timeline across accounts
- Anomaly detection results and baselines
- RCA evidence explorer (logs, metrics, events, traces)
- AI provider usage and cost metrics
- Detection policy effectiveness

**Answer:**
- Unified incident timeline across accounts
- Anomaly detection results and baselines
- RCA evidence explorer (logs, metrics, events, traces)

the rest part of phase 2

### 8. Screenshot generation
For Slack notifications, should the system generate screenshots of OpenSearch dashboards?
- Yes, essential for MVP (requires headless browser or OpenSearch API)
- Nice-to-have, not critical
- No, links are sufficient

**Answer:**
- Nice-to-have, not critical


---

## **AI Provider Selection**

### 9. Provider selection granularity
How should AI provider selection work?
- Global default set by platform admins
- Per-account override capability
- Per-agent-type selection (e.g., RCA agent uses Claude, summarization uses Llama)

**Answer:**
- Per-agent-type selection (e.g., RCA agent uses Claude, summarization uses Llama)


### 10. Provider transparency
Should OpenSearch dashboards show which AI provider was used for each RCA?
- Yes, with cost/latency metrics for comparison
- Yes, but minimal metadata
- No, keep it transparent to users

**Answer:**
- No, keep it transparent to users


---

## **Data Retention & Access**

### 11. Anomaly/RCA history retention
How long should anomaly and RCA results be retained in OpenSearch and DynamoDB?
- 30 days, 90 days, 1 year, configurable?

**Answer:**
configurable, default 90 days

### 12. Cross-account visibility
Should Platform/SRE teams have visibility across all accounts, or IAM-based filtering?

**Answer:**
yes, across all accounts

---

## **Deployment & Operations**

### 13. Multi-region deployment
Should the control plane support multi-region deployment for high availability?
- Single-region initially (which region?)
- Multi-region from the start (active-active or active-passive?)

**Answer:**
- Single-region initially: eu-central-1

### 14. Slack bot deployment
How should the Slack bot be deployed?
- AWS Lambda (serverless, event-driven)
- ECS/Fargate (long-running, websocket-based)
- Combination (Lambda for webhooks, ECS for chat agent)

**Answer:**
- AWS Lambda (serverless, event-driven)


---

## Additional Questions or Notes

**Add any additional context, priorities, or constraints:**

Break up deployment approach for phase 1 into MVP and Phase 1. Highlight in the solution design those for MVP to be picked later.