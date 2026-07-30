"""
Flask app hosted on EC2 that stores/retrieves files from S3.

Credentials are NOT read from environment variables or hardcoded here.
boto3 automatically picks up temporary credentials from the IAM role
attached to the EC2 instance (the "instance profile"), which is the
secure pattern for production workloads.
"""
import os
from datetime import datetime

import boto3
from botocore.exceptions import ClientError
from flask import Flask, render_template, request, redirect, url_for, flash, abort

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "dev-secret-change-me")

# Set this via an environment variable on the instance (see deploy/user_data.sh)
BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

s3_client = boto3.client("s3", region_name=AWS_REGION)


@app.route("/health")
def health():
    """Simple health check endpoint for load balancers / monitoring."""
    return {"status": "ok", "time": datetime.utcnow().isoformat()}, 200


@app.route("/")
def index():
    files = []
    error = None
    if BUCKET_NAME:
        try:
            response = s3_client.list_objects_v2(Bucket=BUCKET_NAME)
            files = [
                {
                    "key": obj["Key"],
                    "size_kb": round(obj["Size"] / 1024, 1),
                    "last_modified": obj["LastModified"].strftime("%Y-%m-%d %H:%M UTC"),
                }
                for obj in response.get("Contents", [])
            ]
        except ClientError as e:
            error = f"Could not list bucket contents: {e.response['Error']['Code']}"
    else:
        error = "S3_BUCKET_NAME is not configured on this instance."

    return render_template("index.html", files=files, bucket=BUCKET_NAME, error=error)


@app.route("/upload", methods=["POST"])
def upload():
    if not BUCKET_NAME:
        flash("No S3 bucket configured.", "error")
        return redirect(url_for("index"))

    uploaded_file = request.files.get("file")
    if not uploaded_file or uploaded_file.filename == "":
        flash("Please choose a file first.", "error")
        return redirect(url_for("index"))

    try:
        s3_client.upload_fileobj(uploaded_file, BUCKET_NAME, uploaded_file.filename)
        flash(f"Uploaded '{uploaded_file.filename}' to S3.", "success")
    except ClientError as e:
        flash(f"Upload failed: {e.response['Error']['Code']}", "error")

    return redirect(url_for("index"))


@app.route("/files/<path:key>")
def download(key):
    """Generate a short-lived presigned URL rather than proxying the file
    or making the bucket public."""
    if not BUCKET_NAME:
        abort(404)
    try:
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": BUCKET_NAME, "Key": key},
            ExpiresIn=300,  # 5 minutes
        )
        return redirect(url)
    except ClientError:
        abort(404)


if __name__ == "__main__":
    # For local testing only. In production this runs behind gunicorn
    # (see deploy/user_data.sh / the systemd unit it creates).
    app.run(host="0.0.0.0", port=5000, debug=True)
