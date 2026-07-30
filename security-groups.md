# Security Groups

A Security Group (SG) is a stateful virtual firewall attached to the
instance's network interface. This project's SG has exactly two inbound
rules:

| Port | Protocol | Source | Why |
|---|---|---|---|
| 22 | TCP | Your IP only (`MY_IP`) | SSH access for administration |
| 80 | TCP | `0.0.0.0/0` | Public HTTP access to the Flask app |

No outbound rules are restricted — the default "allow all outbound" is left
in place so the instance can reach S3 and package repositories.

## Why not open SSH to the world?

Opening port 22 to `0.0.0.0/0` is one of the most common misconfigurations
that leads to compromised EC2 instances (automated bots constantly scan for
it). Scoping the source to your own IP removes that entire attack surface.
If your IP changes, update the rule:

```bash
aws ec2 revoke-security-group-ingress --group-id <SG_ID> --protocol tcp --port 22 --cidr <OLD_IP>/32
aws ec2 authorize-security-group-ingress --group-id <SG_ID> --protocol tcp --port 22 --cidr <NEW_IP>/32
```

## Hardening ideas beyond this project

- Replace direct SSH with **AWS Systems Manager Session Manager**, which
  needs no open inbound port at all.
- Put the instance behind an **Application Load Balancer** and remove the
  public IP from the instance itself; only the ALB's SG allows port 80/443
  from the internet.
- Use a separate SG for the ALB (allows 80/443 from anywhere) and a second
  SG for the instance (allows 80 only from the ALB's SG, not from
  `0.0.0.0/0`).
- Add AWS WAF in front of the ALB for basic request filtering.
