# IAM setup

This project uses two different IAM concepts — it's worth understanding the
difference:

- **IAM user** — for a *person* (you) to run AWS CLI commands from your laptop.
- **IAM role** — for an *AWS resource* (the EC2 instance) to call other AWS
  services (S3) without any long-lived credentials ever touching the instance.

## 1. IAM user (for you, the operator)

If you don't already have one:

```bash
aws iam create-user --user-name flask-project-admin

aws iam attach-user-policy \
  --user-name flask-project-admin \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

aws iam attach-user-policy \
  --user-name flask-project-admin \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam create-access-key --user-name flask-project-admin
```
> In a real environment, scope these down further (e.g. restrict to a region,
> specific resource tags) rather than using the AWS-managed `*FullAccess`
> policies. They're used here to keep the learning project simple.

Save the returned `AccessKeyId` / `SecretAccessKey` and run `aws configure`
locally with them.

## 2. IAM role (for the EC2 instance)

This is the role the running instance assumes to reach S3 — no access keys
are stored on disk.

```bash
# Edit ec2-s3-access-policy.json first: replace YOUR-UNIQUE-BUCKET-NAME
# with your actual bucket name (both occurrences).

# a) Create the role, trusting the EC2 service
aws iam create-role \
  --role-name flask-app-ec2-role \
  --assume-role-policy-document file://ec2-trust-policy.json

# b) Attach the least-privilege S3 policy
aws iam put-role-policy \
  --role-name flask-app-ec2-role \
  --policy-name flask-app-s3-access \
  --policy-document file://ec2-s3-access-policy.json

# c) Create an instance profile and add the role to it
aws iam create-instance-profile \
  --instance-profile-name flask-app-instance-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name flask-app-instance-profile \
  --role-name flask-app-ec2-role
```

That instance profile name (`flask-app-instance-profile`) is what
`deploy/setup_ec2.sh` attaches to the EC2 instance at launch via
`--iam-instance-profile`.

## Verifying it worked

Once the instance is running, SSH in and run:

```bash
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

If you see `flask-app-ec2-role` listed, the instance has successfully
assumed the role and `boto3` inside the Flask app will use it automatically.
