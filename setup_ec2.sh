#!/usr/bin/env bash
#
# Launches the EC2 instance for this project:
#   1. Creates a Security Group (SSH from your IP only, HTTP from anywhere)
#   2. Creates an EC2 key pair (if it doesn't already exist) and saves the .pem
#   3. Launches an Amazon Linux 2023 instance with the IAM instance profile
#      created via iam/README.md, passing deploy/user_data.sh as bootstrap code
#
# Required environment variables:
#   BUCKET_NAME   - the S3 bucket the app will read/write (must already exist)
#   KEY_NAME      - name for the EC2 key pair (default: flask-app-key)
#   MY_IP         - your public IP in CIDR form, e.g. 203.0.113.5/32
#
# Optional:
#   INSTANCE_PROFILE_NAME - IAM instance profile name (default: flask-app-instance-profile)
#   REGION                - AWS region (default: us-east-1)
#   INSTANCE_TYPE          - default: t2.micro (free-tier eligible)

set -euo pipefail

: "${BUCKET_NAME:?Set BUCKET_NAME to your S3 bucket name}"
: "${MY_IP:?Set MY_IP to your public IP in CIDR form, e.g. 203.0.113.5/32}"
KEY_NAME="${KEY_NAME:-flask-app-key}"
INSTANCE_PROFILE_NAME="${INSTANCE_PROFILE_NAME:-flask-app-instance-profile}"
REGION="${REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"
SG_NAME="flask-app-sg"

echo "==> Looking up latest Amazon Linux 2023 AMI..."
AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --region "$REGION" --query "Parameters[0].Value" --output text)
echo "    Using AMI: $AMI_ID"

echo "==> Getting default VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --region "$REGION" --query "Vpcs[0].VpcId" --output text)

echo "==> Creating security group ($SG_NAME)..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "Flask app: SSH from admin IP, HTTP from anywhere" \
  --vpc-id "$VPC_ID" --region "$REGION" \
  --query "GroupId" --output text 2>/dev/null || \
  aws ec2 describe-security-groups --filters Name=group-name,Values="$SG_NAME" \
  --region "$REGION" --query "SecurityGroups[0].GroupId" --output text)
echo "    SG_ID: $SG_ID"

echo "==> Authorizing SSH (22) from $MY_IP..."
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --region "$REGION" \
  --protocol tcp --port 22 --cidr "$MY_IP" 2>/dev/null || echo "    (rule already exists)"

echo "==> Authorizing HTTP (80) from anywhere..."
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --region "$REGION" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 2>/dev/null || echo "    (rule already exists)"

echo "==> Ensuring key pair ($KEY_NAME) exists..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" \
    --query "KeyMaterial" --output text > "${KEY_NAME}.pem"
  chmod 400 "${KEY_NAME}.pem"
  echo "    Saved ${KEY_NAME}.pem"
else
  echo "    Key pair already exists, reusing it (make sure you still have the .pem)"
fi

echo "==> Rendering user-data with your bucket name..."
sed "s/__BUCKET_NAME__/${BUCKET_NAME}/g; s/__REGION__/${REGION}/g" \
  "$(dirname "$0")/user_data.sh" > /tmp/rendered_user_data.sh

echo "==> Launching instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile "Name=${INSTANCE_PROFILE_NAME}" \
  --user-data "file:///tmp/rendered_user_data.sh" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=flask-s3-demo}]' \
  --region "$REGION" \
  --query "Instances[0].InstanceId" --output text)

echo "==> Waiting for instance to enter 'running' state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo ""
echo "Instance launched: $INSTANCE_ID"
echo "Public IP:         $PUBLIC_IP"
echo ""
echo "SSH in with:   ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
echo "App URL:       http://${PUBLIC_IP}/   (give the instance ~1-2 min to finish bootstrapping)"
