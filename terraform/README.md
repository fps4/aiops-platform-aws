# Terraform Infrastructure

This directory contains all Terraform configurations for the AIOps platform.

## Structure

```
terraform/
├── modules/              # Reusable Terraform modules
│   ├── iam/             # IAM roles and policies
│   ├── data-stores/     # S3, DynamoDB, OpenSearch, Timestream
│   ├── compute/         # Lambda functions, Step Functions
│   ├── ingestion/       # Kinesis Firehose, EventBridge
│   └── observability/   # CloudWatch alarms, dashboards
├── environments/        # Environment-specific configurations
│   ├── dev/            # Development environment
│   ├── staging/        # Staging environment
│   └── prod/           # Production environment
└── member-account/     # Cross-account IAM setup
```

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials
- S3 bucket for Terraform state (created via bootstrap script)

## Getting Started

### 1. Bootstrap Terraform State Backend

```bash
cd /path/to/aiops-platform
./scripts/bootstrap-terraform-state.sh
```

This script will:
- Prompt for your AWS Account ID (12 digits)
- Create S3 bucket: `{account-id}-aiops-platform-terraform-state`
- Enable versioning, encryption, and block public access

### 2. Update Backend Configuration

Edit `terraform/environments/dev/main.tf` and replace `ACCOUNT_ID` with your actual AWS account ID:

```hcl
backend "s3" {
  bucket = "123456789012-aiops-platform-terraform-state"  # Your account ID
  key    = "dev/terraform.tfstate"
  region = "eu-central-1"
}
```

Edit `terraform/environments/dev/dev.tfvars`:
- Replace placeholder account IDs with your actual AWS account IDs
- Update any other configuration values as needed

### 3. Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

### 4. Review Plan

```bash
terraform plan -var-file=dev.tfvars
```

### 5. Deploy Infrastructure

```bash
terraform apply -var-file=dev.tfvars
```

## Modules

### IAM Module
Creates IAM roles for:
- Lambda execution (with permissions for DynamoDB, S3, OpenSearch, Bedrock, etc.)
- Step Functions execution
- Kinesis Firehose delivery
- Cross-account read access

### Data Stores Module
Creates:
- **S3 Buckets**: raw logs, audit logs, dashboard screenshots
- **DynamoDB Tables**: anomalies, events, policy_store, agent_state, audit_logs_index
- **OpenSearch Serverless**: collection for indexed logs
- **Timestream** (optional): database and table for metrics - disabled by default, requires AWS Support approval

To enable Timestream, set `enable_timestream = true` in `resources.tf` after contacting AWS Support.

## Managing Multiple Environments

Each environment (dev, staging, prod) has its own:
- `<env>.tfvars` - Variable values
- `main.tf` - Provider and backend configuration
- `resources.tf` - Module calls and resources
- State file in S3 (`<env>/terraform.tfstate`)

To deploy to staging:
```bash
cd terraform/environments/staging
terraform init
terraform apply -var-file=staging.tfvars
```

## Outputs

After deployment, Terraform outputs key resource identifiers:
- IAM role ARNs
- S3 bucket names
- DynamoDB table names
- OpenSearch endpoint
- Timestream database/table names

View outputs:
```bash
terraform output
```

## State Management

- **Backend**: S3 bucket `{account-id}-aiops-platform-terraform-state`
- **State file**: `<env>/terraform.tfstate`
- **Locking**: None (S3-only backend)
- **Versioning**: Enabled on state bucket

The bucket name includes your AWS account ID for global uniqueness.

## Security Notes

- All resources use least-privilege IAM policies
- Encryption at rest enabled for S3, DynamoDB
- OpenSearch Serverless uses IAM authentication
- Secrets stored in AWS Secrets Manager
- Configuration in SSM Parameter Store

## Troubleshooting

### Error: Bucket already exists
If the state bucket already exists, the bootstrap script will skip creation. If you need to recreate it, delete the bucket first:
```bash
aws s3 rb s3://{account-id}-aiops-platform-terraform-state --force
```

### Error: OpenSearch access denied
Ensure your AWS credentials have permissions to create OpenSearch Serverless collections. Check the IAM principal in the data access policy.

### Error: Invalid account ID
Update the placeholder account IDs in `dev.tfvars` with your actual AWS account IDs (12-digit numbers).
