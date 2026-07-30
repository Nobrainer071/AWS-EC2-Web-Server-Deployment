#!/bin/bash
# Runs automatically on first boot (passed as EC2 user-data).
# __BUCKET_NAME__ and __REGION__ are substituted by setup_ec2.sh before launch.
set -e

dnf update -y
dnf install -y python3 python3-pip git

APP_DIR=/opt/flask-s3-app
git clone https://github.com/YOUR-USERNAME/ec2-flask-s3-deployment.git "$APP_DIR" || true
cd "$APP_DIR/app"

pip3 install -r requirements.txt

# Environment file read by the systemd service
cat > /etc/flask-s3-app.env <<EOF
S3_BUCKET_NAME=__BUCKET_NAME__
AWS_REGION=__REGION__
FLASK_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
EOF

# systemd unit so the app survives reboots and restarts on crash
cat > /etc/systemd/system/flask-s3-app.service <<'EOF'
[Unit]
Description=Flask + S3 demo app
After=network.target

[Service]
EnvironmentFile=/etc/flask-s3-app.env
WorkingDirectory=/opt/flask-s3-app/app
ExecStart=/usr/bin/python3 -m gunicorn --bind 0.0.0.0:80 --workers 2 app:app
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flask-s3-app
systemctl start flask-s3-app
