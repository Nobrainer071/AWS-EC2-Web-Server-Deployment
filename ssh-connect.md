# Connecting via SSH

## 1. Permissions on the key file

AWS requires the private key to not be readable by others, or SSH will
refuse to use it:

```bash
chmod 400 flask-app-key.pem
```

## 2. Connect

```bash
ssh -i flask-app-key.pem ec2-user@<PUBLIC_IP>
```

`ec2-user` is the default login user for Amazon Linux AMIs (use `ubuntu` for
Ubuntu AMIs, `admin` for Debian).

## 3. Useful checks once connected

```bash
# Confirm the app is running
sudo systemctl status flask-s3-app

# Tail logs live
sudo journalctl -u flask-s3-app -f

# Confirm the instance has assumed the IAM role
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

## Common connection problems

| Symptom | Likely cause |
|---|---|
| `Connection timed out` | Your current IP isn't allowed in the SG — see `docs/security-groups.md` |
| `Permission denied (publickey)` | Wrong username for the AMI, or wrong `.pem` file |
| `UNPROTECTED PRIVATE KEY FILE` warning | Run `chmod 400` on the `.pem` file |
| App loads SSH but not HTTP | user-data may still be running — wait ~1-2 min, then check `journalctl -u cloud-init -f` |
