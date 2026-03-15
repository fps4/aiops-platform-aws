# Security & Compliance Guide

This guide outlines controls and operating practices for secure, auditable use of the AIOps Agentic System.

## Control objectives

- Ensure least-privilege access to telemetry and platform operations.
- Maintain end-to-end auditability for access, policy changes, and incident actions.
- Protect sensitive data in logs, traces, and alerts.

## IAM and access model

- Use IAM roles only; no static credentials in code or docs.
- Grant `ssm:StartSession` only to authorized operators.
- Scope access by environment and role responsibilities.

## Data handling

- Avoid PII/secrets in application logs and trace attributes.
- Use structured logging with explicit allowlisted fields.
- Ensure storage retention and TTL settings match policy requirements.

## Audit and change governance

- Track policy changes via PR review and deployment history.
- Review CloudTrail for SSM sessions and privileged actions.
- Require peer approval for production policy updates and sensitive config changes.

## Security incident support

- Correlate suspicious patterns across logs, traces, and account boundaries.
- Work with platform and service teams on containment and evidence capture.
- Preserve relevant telemetry artifacts for post-incident investigation.
