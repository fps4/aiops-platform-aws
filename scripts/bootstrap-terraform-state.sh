#!/bin/bash

# Bootstrap script to create Terraform state backend in S3
# Run this once before deploying infrastructure

set -e

REGION="eu-central-1"
PROJECT_PREFIX="aiops-platform"

echo "==================================="
echo "Terraform State Backend Setup"
echo "==================================="
echo ""

# Prompt for AWS Account ID
read -p "Enter AWS Account ID (12 digits): " ACCOUNT_ID

# Validate account ID format
if ! [[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    echo "❌ Error: Account ID must be exactly 12 digits"
    exit 1
fi

BUCKET_NAME="${ACCOUNT_ID}-${PROJECT_PREFIX}-terraform-state"

echo ""
echo "Configuration:"
echo "  Account ID: $ACCOUNT_ID"
echo "  Bucket:     $BUCKET_NAME"
echo "  Region:     $REGION"
echo ""

# Check if bucket exists
if aws s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating S3 bucket..."
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
    
    echo "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    echo "Enabling encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
          "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
              "SSEAlgorithm": "AES256"
            }
          }]
        }'
    
    echo "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    echo ""
    echo "✅ Terraform state backend created successfully!"
else
    echo "✅ Bucket already exists, skipping creation."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Update terraform/environments/dev/main.tf:"
echo ""
echo "   backend \"s3\" {"
echo "     bucket = \"$BUCKET_NAME\""
echo "     key    = \"dev/terraform.tfstate\""
echo "     region = \"$REGION\""
echo "   }"
echo ""
echo "2. Run terraform init:"
echo ""
echo "   cd terraform/environments/dev"
echo "   terraform init"
echo ""

