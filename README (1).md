# AWS EC2 Web Server Deployment — Flask + S3 + IAM

A hands-on AWS project that deploys a Flask web application on an EC2 instance,
uses an IAM role (not hardcoded keys) to talk to S3 for file storage, and is
locked down with a properly scoped Security Group. Built as a learning project
covering the core AWS fundamentals: **EC2, Security Groups, SSH, IAM, and S3**.

## What this project demonstrates

| Skill | Where it happens |
|---|---|
| Launching EC2 instances | `deploy/setup_ec2.sh` |
| Configuring Security Groups | `deploy/setup_ec2.sh`, `docs/security-groups.md` |
| Connecting via SSH | `docs/ssh-connect.md` |
| Hosting a Flask application | `app/app.py`, `deploy/user_data.sh` |
| Managing storage with S3 | `app/app.py` (upload/download/list), `iam/ec2-s3-access-policy.json` |
| Creating IAM users and roles | `iam/README.md`, `iam/ec2-s3-access-policy.json`, `iam/ec2-trust-policy.json` |

## Architecture

```
                     ┌─────────────────────────────┐
   Internet  ───SSH───▶  Security Group (22, 80)    │
   (you)     ───HTTP──▶  ┌───────────────────────┐  │
                     │  │   EC2 Instance         │  │
                     │  │   - Amazon Linux 2023  │  │
                     │  │   - Flask app (gunicorn)│ │
                     │  │   - IAM Instance Role  │──┼──▶  S3 Bucket
                     │  └───────────────────────┘  │      (file storage)
                     └─────────────────────────────┘
```

The EC2 instance never stores AWS access keys. It assumes an **IAM role**
attached at launch (instance profile), which grants only the specific S3
permissions it needs — this is the pattern real production systems use.

## Repo layout

```
ec2-flask-s3-deployment/
├── app/                    # The Flask application
│   ├── app.py              # Routes: /, /upload, /files, /files/<key>, /health
│   ├── requirements.txt
│   └── templates/index.html
├── deploy/
│   ├── setup_ec2.sh        # AWS CLI: creates SG, key pair, launches instance
│   └── user_data.sh        # Bootstrap script that runs on first boot
├── iam/
│   ├── ec2-s3-access-policy.json   # Least-privilege S3 policy for the role
│   ├── ec2-trust-policy.json       # Trust policy so EC2 can assume the role
│   └── README.md                   # Step-by-step IAM user + role creation
├── docs/
│   ├── security-groups.md  # Why each SG rule exists, how to lock it down further
│   └── ssh-connect.md      # Key pair handling and SSH connection steps
├── .github/workflows/deploy.yml   # Optional CI/CD: push to main -> redeploy
└── README.md
```

## Quick start

### 1. Prerequisites
- AWS account + [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured (`aws configure`)
- An IAM **user** with permissions to create EC2/IAM/S3 resources (see `iam/README.md`)
- `jq` installed locally (used by the setup script to parse JSON)

### 2. Create the S3 bucket
```bash
aws s3 mb s3://YOUR-UNIQUE-BUCKET-NAME --region us-east-1
```

### 3. Create the IAM role the EC2 instance will use
Follow `iam/README.md` — it creates a role with only `s3:GetObject`,
`s3:PutObject`, and `s3:ListBucket` on your bucket, and an instance profile
to attach that role to EC2.

### 4. Launch the EC2 instance
```bash
export BUCKET_NAME=YOUR-UNIQUE-BUCKET-NAME
export KEY_NAME=flask-app-key
export MY_IP=$(curl -s ifconfig.me)/32
bash deploy/setup_ec2.sh
```
This script:
1. Creates a Security Group allowing SSH (22) only from `MY_IP` and HTTP (80) from anywhere
2. Creates/reuses an EC2 key pair and saves the `.pem` locally
3. Launches an Amazon Linux 2023 instance with the IAM instance profile attached
4. Passes `deploy/user_data.sh` as user-data, which installs Python, clones this repo, installs `gunicorn`, and starts the Flask app as a `systemd` service on port 80

### 5. Connect and verify
```bash
chmod 400 flask-app-key.pem
ssh -i flask-app-key.pem ec2-user@<PUBLIC_IP>
```
See `docs/ssh-connect.md` for details and troubleshooting.

Then open `http://<PUBLIC_IP>/` in a browser — you'll see a simple upload
form that writes files straight to your S3 bucket, and a page listing what's
currently stored there.

### 6. Clean up (avoid charges)
```bash
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
aws s3 rb s3://YOUR-UNIQUE-BUCKET-NAME --force
```

## Security notes
- No AWS credentials are ever placed on the instance — access to S3 comes
  entirely from the attached IAM role.
- SSH is restricted to your IP by default; see `docs/security-groups.md` for
  how to tighten HTTP access too (e.g., behind a load balancer or your IP only).
- The S3 bucket policy/IAM policy grants only the three actions the app
  actually needs — not full `s3:*`.

## Optional: CI/CD
`.github/workflows/deploy.yml` shows how you'd extend this so a `git push`
to `main` re-deploys the app to the running instance over SSH using a GitHub
Actions secret for the private key. Disabled by default — see comments in the file.
