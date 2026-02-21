# Subscribing an Application to the AIOps Platform

This guide explains how to route CloudWatch logs from an application into the AIOps platform so that they are normalised, stored, and monitored for anomalies.

---

## How ingestion works

```
Your application
  └─ CloudWatch log group
       └─ Subscription filter ──► Kinesis Firehose (central account)
                                       ├─ Lambda: normalise to canonical schema
                                       ├─ OpenSearch: indexed for anomaly detection
                                       └─ S3: raw archive (partitioned by date)
```

A **subscription filter** is a CloudWatch Logs rule that forwards every matching log event to a destination in real time. The platform exposes two destinations depending on where your application lives:

| Scenario | Destination type | Destination ARN |
|---|---|---|
| Same AWS account as the platform | Kinesis Firehose stream | `module.ingestion.firehose_stream_arn` |
| Different AWS account | CloudWatch Logs destination | `module.ingestion.cloudwatch_logs_destination_arn` |

CloudWatch Logs allows **one subscription filter per log group**. If a log group already has a subscription filter (e.g. forwarding to a SIEM), contact the platform team to discuss options.

---

## Prerequisites

- The platform is deployed and its Terraform outputs are accessible.
  Run `./scripts/get-config.sh dev` to populate `.env` with current values.
- For cross-account: you have Terraform access to the member account.
- You know the CloudWatch log group name(s) for your application
  (e.g. `/aws/lambda/payment-service`, `/aws/ecs/checkout-api`).

---

## Option A — Same-account subscription (Terraform module)

Use this when your application runs in the **same AWS account as the platform**.

Add one module block per log group to `terraform/environments/dev/resources.tf`:

```hcl
module "logs_<application_name>" {
  source = "../../modules/log-subscription"

  environment      = var.environment
  project_prefix   = var.project_prefix
  application_name = "<application_name>"           # short, lowercase, hyphen-separated
  log_group_name   = "/aws/lambda/<function-name>"  # exact log group name

  firehose_stream_arn                   = module.ingestion.firehose_stream_arn
  cloudwatch_logs_subscription_role_arn = module.ingestion.cloudwatch_logs_subscription_role_arn
}
```

**Example — three applications:**

```hcl
module "logs_payment_api" {
  source           = "../../modules/log-subscription"
  environment      = var.environment
  project_prefix   = var.project_prefix
  application_name = "payment-api"
  log_group_name   = "/aws/lambda/payment-api"
  firehose_stream_arn                   = module.ingestion.firehose_stream_arn
  cloudwatch_logs_subscription_role_arn = module.ingestion.cloudwatch_logs_subscription_role_arn
}

module "logs_checkout_ecs" {
  source           = "../../modules/log-subscription"
  environment      = var.environment
  project_prefix   = var.project_prefix
  application_name = "checkout-ecs"
  log_group_name   = "/aws/ecs/checkout-service"
  firehose_stream_arn                   = module.ingestion.firehose_stream_arn
  cloudwatch_logs_subscription_role_arn = module.ingestion.cloudwatch_logs_subscription_role_arn
}

module "logs_cloudtrail" {
  source           = "../../modules/log-subscription"
  environment      = var.environment
  project_prefix   = var.project_prefix
  application_name = "cloudtrail"
  log_group_name   = "aws-controltower/CloudTrailLogs"
  firehose_stream_arn                   = module.ingestion.firehose_stream_arn
  cloudwatch_logs_subscription_role_arn = module.ingestion.cloudwatch_logs_subscription_role_arn
}
```

Then apply:

```bash
cd terraform/environments/dev
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

---

## Option B — Cross-account subscription

Use this when your application runs in a **different AWS account** (a "member account").

### Step 1 — Retrieve the destination ARN

```bash
cd terraform/environments/dev
terraform output cloudwatch_logs_destination_arn
# e.g. arn:aws:logs:eu-central-1:648349967087:destination:aiops-platform-dev-logs-destination
```

### Step 2 — Add the subscription filter in the member account

In the member account's Terraform, add one block per log group. No special IAM role is required on the member side — the central account's destination policy already permits it.

```hcl
resource "aws_cloudwatch_log_subscription_filter" "aiops_<application_name>" {
  name            = "aiops-platform-<application_name>"
  log_group_name  = "/aws/lambda/<function-name>"
  filter_pattern  = ""
  destination_arn = "<destination_arn_from_step_1>"
}
```

**Example:**

```hcl
resource "aws_cloudwatch_log_subscription_filter" "aiops_payments" {
  name            = "aiops-platform-payments"
  log_group_name  = "/aws/lambda/payments-prod"
  filter_pattern  = ""
  destination_arn = "arn:aws:logs:eu-central-1:648349967087:destination:aiops-platform-dev-logs-destination"
}
```

No `role_arn` is needed here — cross-account destinations handle auth at the destination level.

---

## Filter patterns

The `filter_pattern` field controls which log events are forwarded. An empty string (`""`) forwards everything.

| Goal | Pattern |
|---|---|
| All logs | `""` |
| Errors and warnings only | `"?ERROR ?WARN ?error ?warn"` |
| Structured JSON logs with log level | `"{ $.level = \"ERROR\" }"` |
| Lambda cold starts | `"Init Duration"` |
| HTTP 5xx responses | `"HTTP/1.1 5"` |

Narrowing the filter reduces Firehose ingestion cost and keeps OpenSearch free of noise. For anomaly detection to work correctly, **ERROR and WARN events must always be included**.

---

## Log format recommendations

The normalisation Lambda maps incoming fields to the [canonical schema](../solution-design.md). The more closely your logs match it, the richer the anomaly detection context will be.

**Recommended structured JSON fields:**

```json
{
  "timestamp": "2026-02-21T14:30:00.000Z",
  "level": "ERROR",
  "service": "payment-api",
  "message": "Payment gateway timeout after 30s",
  "deployment_version": "v2.4.1",
  "duration_ms": 30012,
  "account_id": "234567890123",
  "region": "eu-central-1"
}
```

Fields the normaliser can automatically extract if your logs use them:

| Your field | Canonical field |
|---|---|
| `timestamp` or `@timestamp` | `timestamp` |
| `level`, `severity`, `logLevel`, `log_level` | `log_level` |
| `msg`, `message` | `message` |
| `service` | `service` |
| `logGroup` (injected by CWL) | `service` (last path segment) |
| `accountId` or `account_id` | `account_id` |
| `awsRegion` or `region` | `region` |
| `appVersion` or `deployment_version` | `deployment_version` |

Fields not in the canonical schema are preserved under `_raw` and stored in both OpenSearch and S3.

Plain-text logs are accepted but produce lower-quality anomaly detection because metric extraction relies on structured fields like `duration_ms`.

---

## Verifying data is flowing

**1. Check Firehose delivery metrics (1–2 min after applying):**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Firehose \
  --metric-name IncomingRecords \
  --dimensions Name=DeliveryStreamName,Value=aiops-platform-dev-log-stream \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum \
  --region eu-central-1
```

**2. Check S3 for raw log objects (arrives after the 60s Firehose buffer):**

```bash
aws s3 ls s3://aiops-platform-dev-raw-logs/logs/ --recursive | tail -10
```

**3. Query OpenSearch for your service's index:**

The log normaliser creates indices named `logs-<service>-<date>` (e.g. `logs-payment-api-2026.02.21`). Use the OpenSearch Dashboards Discover tab or the API:

```bash
curl -X GET "${OPENSEARCH_ENDPOINT}/logs-payment-api-*/_count" \
  -H "Content-Type: application/json" \
  --aws-sigv4 "aws:amz:eu-central-1:aoss"
```

---

## Enabling anomaly detection for your application

Subscribing a log group only starts ingestion. To enable active anomaly detection you also need a **detection policy** in DynamoDB.

Create a YAML entry in `policies/default-policies.yaml`:

```yaml
- policy_id: "policy-payment-api"
  service: "payment-api"
  account_id: "234567890123"   # the account where the app runs
  enabled: true
  sensitivity: "medium"         # low | medium | high
  metrics:
    - duration_ms
    - error_count
  detection:
    type: statistical
    window_days: 7
  actions:
    alert: true
    run_rca: true
```

Then load it:

```bash
scripts/load-policies.sh --file policies/default-policies.yaml
```

See [`scripts/validate-policy.py`](../../scripts/validate-policy.py) to validate before loading.

---

## Troubleshooting

**Subscription filter fails to create**
Verify the log group exists before the filter is applied. CloudWatch Logs creates log groups lazily (on first log event for Lambda/ECS). Either deploy the application first, or create the log group explicitly:
```bash
aws logs create-log-group --log-group-name /aws/lambda/my-function --region eu-central-1
```

**Records arrive in S3 but not in OpenSearch**
Check the log-normaliser Lambda for errors:
```bash
aws logs tail /aws/lambda/aiops-platform-dev-log-normalizer --follow --region eu-central-1
```
Common cause: the OpenSearch collection's data access policy does not include the Lambda execution role principal.

**`ProcessingFailed` records in the Firehose error prefix**
The normaliser received a record it could not parse (non-JSON, oversized, etc.). Raw records are preserved under `s3://aiops-platform-dev-raw-logs/errors/`. The batch continues — failed records do not block other events.

**Cross-account filter gets `AccessDeniedException`**
The CWL destination policy uses `aws:PrincipalOrgID`. If the member account is not in the same AWS Organisation, contact the platform team to add the account ID explicitly to the destination policy.
