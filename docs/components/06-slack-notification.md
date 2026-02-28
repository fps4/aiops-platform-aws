# Slack Notification

## Alert Payload (MVP)

Alerts are sent via Slack Incoming Webhooks using Block Kit for structured formatting.

```json
{
  "channel": "#aiops-alerts",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "🚨 Latency Spike Detected: api-gateway (prod-account-123)"
      }
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*What Happened:*\nP95 latency increased from 150ms to 1200ms (700% deviation)"
        },
        {
          "type": "mrkdwn",
          "text": "*Confidence:*\nHigh (85%)"
        }
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Probable Root Cause:*\nDeployment v2.3.1 at 09:15 UTC introduced slow DB query in /users endpoint. Similar pattern observed in incident INC-2024-045."
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Key Evidence:*\n• Deployment timestamp correlates with spike start\n• Error logs show 'connection timeout' for user-db\n• Traffic to /users endpoint increased 3x post-deploy"
      }
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": { "type": "plain_text", "text": "View Dashboard" },
          "url": "http://localhost:3000/d/rca-explorer/rca-evidence-explorer?var-service=api-gateway&var-account_id=123456789012&from=2026-02-14T09:00:00Z&to=2026-02-14T10:30:00Z",
          "style": "primary"
        }
      ]
    }
  ]
}
```

## Grafana Deep-Link Generation

The Slack notifier constructs a Grafana URL with template variable parameters pre-filled:

- `from` / `to`: Incident timeframe ±30 minutes
- `var-service`: Affected service
- `var-account_id`: Affected account
- `var-anomaly_id`: Direct link to anomaly details

The base URL comes from the `GRAFANA_URL` environment variable (set to the Grafana EC2 private IP + port 3000 via SSM Parameter Store).

## Screenshot Generation (Phase 1)

A Lambda with headless Chromium captures a dashboard screenshot and attaches it to the Slack message.

```python
from playwright.sync_api import sync_playwright

def generate_dashboard_screenshot(dashboard_url: str) -> str:
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(extra_http_headers={
            "Authorization": f"Bearer {grafana_api_key}"
        })

        page.goto(dashboard_url)
        page.wait_for_load_state("networkidle")
        screenshot_bytes = page.screenshot(full_page=False)

        # Upload to S3 with 24h expiry
        s3_url = upload_to_s3_with_expiry(screenshot_bytes, ttl_hours=24)
        browser.close()
        return s3_url

# Attach to Slack message
{
  "type": "image",
  "image_url": s3_url,
  "alt_text": "Dashboard screenshot for incident abc123"
}
```
