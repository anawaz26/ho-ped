# ============================================================
# PPE Certification Platform - Stack Variables
# HLD-PPE-2026-001
# ============================================================

# AWS target region - must be eu-west-2 (London) per HLD §7.1.2 design decision

# AWS account ID - used for namespacing globally-unique resources and composing role ARNs
variable "aws_account_id" {
  type        = string
  description = "AWS account ID for the target account."
}

variable "region" {
  type        = string
  description = "AWS region. Must be eu-west-2 (London) per HLD-PPE-2026-001 §7.1.2."
}

# Deployment environment label (sandbox | production-blue | production-green)
variable "environment" {
  type        = string
  description = "Deployment environment identifier. Used to namespace resources."
}

# IAM role assumed by HCP Terraform via OIDC workload identity (no long-lived keys)
variable "role_arn" {
  type        = string
  description = "ARN of the IAM role for HCP Terraform to assume via OIDC web identity."
}

# SSH key pair name for EC2 instances (bastion, DMZ, APP)
# Key managed via Ansible (HLD §5.11.2 / STRIDE R1 control)
variable "bastion_key_name" {
  type        = string
  description = "EC2 key pair name for SSH access to bastion, DMZ, and APP instances."
}

# Encircle VPN egress IP - restricts bastion SSH to VPN tunnel only
# STRIDE §7.5 / HLD §5.8.4 - SSH must never be open to 0.0.0.0/0
variable "encircle_vpn_cidr" {
  type        = string
  description = "Encircle VPN egress CIDR (e.g. x.x.x.x/32). SSH access restricted to this IP only."
}

# Cloudflare published IPv4 egress ranges - DMZ security group restricts HTTPS ingress to these only
# HLD §5.5.3 / STRIDE §7.1 - origin IP protection; keep up to date with https://www.cloudflare.com/ips-v4
variable "cloudflare_ip_ranges" {
  type        = list(string)
  description = "Cloudflare published IPv4 egress ranges. DMZ SG restricts HTTPS ingress to these only."
}

# RDS MariaDB admin password - must be sourced from HCP Terraform variable set (sensitive)
# STRIDE R8 - credentials must not be stored in plaintext or version control
variable "db_password" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "RDS MariaDB admin password. Must be set as a sensitive variable in HCP Terraform. Never commit to source control."
}

# Email address for CloudWatch alarm notifications (HLD §6.1 Alerting Strategy)
# Subscribed to the ped-alerts SNS topic. Use an Encircle ops distribution list.
variable "ops_alert_email" {
  type        = string
  description = "Ops team email address for CloudWatch alarm notifications via SNS."
}
