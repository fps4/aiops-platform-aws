# Product Design

## Design philosophy

Investigate first, alert with answers. The UX should minimize cognitive load during incidents by delivering concise conclusions and one-click access to supporting evidence.

## User journeys

### 1) Autonomous pre-investigation

Trigger: anomaly detection event.

System behavior before user sees an alert:
1. Deduplicate and suppress repeated anomalies.
2. Correlate infrastructure, application, and deployment context.
3. Compare with historical incidents and recent changes.
4. Generate probable RCA with confidence and evidence.
5. Attach recommendations/runbook mappings.

Outcome: a structured incident summary ready for operator review.

### 2) Slack-first alert review

Actor: on-call Platform/SRE engineer.

Alert content:
- What changed and where
- Probable cause + confidence level
- Why the model/agent thinks so (short evidence summary)
- Next best action or runbook link
- Deep-link to Grafana dashboard scoped to service + timeframe

Success condition: engineer understands likely cause and urgency within seconds.

### 3) Dashboard-based evidence drilldown

Actor: engineer validating or disproving the RCA.

Pre-built dashboard intents:
- Unified incident timeline
- Anomaly and baseline comparison
- RCA evidence explorer

Navigation:
- Slack deep-link opens with zero manual filter setup.
- Engineer can pivot by account/service/time and share findings.

## Information architecture

### Slack payload structure

- Incident title and severity
- Scope metadata (account, region, service, environment)
- RCA summary with confidence
- Key evidence bullets
- Recommendation and runbook links
- Dashboard deep-link

### Policy authoring UX (IaC-native)

Primary method:
- YAML/JSON policy in Git
- Terraform apply to policy store
- Runtime components reload policy

Design intent:
- No custom admin UI required for MVP
- Versioned, reviewable, and auditable change flow

## UX constraints and guardrails

- Avoid alert spam by suppression windows and dedupe keys.
- Keep confidence explicit; avoid definitive language for low-confidence cases.
- Preserve human approval boundaries for any operational action.
- Ensure accessibility/readability in Slack message formatting.

## Future interaction design (post-MVP)

- Slack actions: acknowledge, snooze, escalate
- Conversational Q&A over observability datasets
- Feedback controls for RCA quality to improve future relevance

