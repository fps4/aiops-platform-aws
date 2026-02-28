# SSM Access Guide

All EC2 instances in this platform (ClickHouse, Grafana) have no SSH key pairs and no inbound port 22. Access is via **AWS SSM Session Manager** — controlled by IAM, audited in CloudTrail, no bastion host required.

## Prerequisites

```bash
# AWS CLI v2
aws --version

# SSM Session Manager plugin
# macOS
brew install --cask session-manager-plugin

# Linux
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/ssm-plugin.deb
sudo dpkg -i /tmp/ssm-plugin.deb

# Verify
session-manager-plugin --version
```

Your IAM user/role needs `ssm:StartSession` permission on the target instances.

---

## Get Instance IDs

```bash
cd terraform/environments/dev

terraform output -raw clickhouse_instance_id   # e.g. i-0abc123def456789a
terraform output -raw grafana_instance_id       # e.g. i-0def456abc789012b
```

---

## Interactive Shell

```bash
# ClickHouse instance
aws ssm start-session \
  --target $(terraform -chdir=terraform/environments/dev output -raw clickhouse_instance_id) \
  --region eu-central-1

# Grafana instance
aws ssm start-session \
  --target $(terraform -chdir=terraform/environments/dev output -raw grafana_instance_id) \
  --region eu-central-1
```

---

## Port Forwarding

### Grafana (port 3000)

```bash
aws ssm start-session \
  --target $(terraform -chdir=terraform/environments/dev output -raw grafana_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}' \
  --region eu-central-1
```

Then open **http://localhost:3000** in your browser.

Default credentials: `admin` / `admin` (change on first login).

### ClickHouse HTTP API (port 8123)

```bash
aws ssm start-session \
  --target $(terraform -chdir=terraform/environments/dev output -raw clickhouse_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8123"],"localPortNumber":["8123"]}' \
  --region eu-central-1
```

Then query ClickHouse locally:

```bash
# Health check
curl http://localhost:8123/ping

# Run SQL
curl http://localhost:8123 --data "SELECT version()"

# Using clickhouse-client (if installed locally)
clickhouse-client --host localhost --port 9000

# Show databases
curl http://localhost:8123 --data "SHOW DATABASES"

# Query logs
curl http://localhost:8123 --data "SELECT count() FROM aiops.logs"
```

---

## Useful On-Instance Commands

Once you have a shell on the ClickHouse instance:

```bash
# Check service status
sudo systemctl status clickhouse-server

# View logs
sudo journalctl -u clickhouse-server -f

# Run SQL interactively
clickhouse-client

# Check data volume mount
df -h /var/lib/clickhouse
lsblk
```

On the Grafana instance:

```bash
# Check service status
sudo systemctl status grafana-server

# View logs
sudo journalctl -u grafana-server -f

# Restart after config change
sudo systemctl restart grafana-server

# List installed plugins
grafana-cli plugins ls
```

---

## Troubleshooting

**`SessionManagerPlugin is not found`**
Install the SSM plugin (see Prerequisites above).

**`An error occurred (TargetNotConnected)`**
The SSM agent on the instance is not reachable. Check:
```bash
# Is the instance running?
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].State.Name'

# Is the SSM agent running? (shell on instance via EC2 console if needed)
sudo systemctl status amazon-ssm-agent
```

Common causes: instance still booting after launch, SSM agent not yet started, or IAM instance profile missing `AmazonSSMManagedInstanceCore`.

**Port forwarding session drops**
The session has a default idle timeout. Re-run the `start-session` command to reconnect. The service (Grafana/ClickHouse) keeps running — only the tunnel drops.

**ClickHouse not responding after first deploy**
The data EBS volume is attached by Terraform after the instance launches. If ClickHouse started before the volume was mounted, restart it:
```bash
sudo mount -a
sudo systemctl restart clickhouse-server
```
