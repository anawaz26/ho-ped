# ============================================================
# PPE Certification Platform - HCP Terraform Stack Deployments
# HLD-PPE-2026-001 | Blue/Green model (HLD §5.3.1 / §5.11.3)
# ============================================================

# --- OIDC IDENTITY TOKEN (GA format - defined in tfdeploy.hcl) ---
# Generates a JWT for each deployment, used by the AWS provider to
# assume the stack role via OIDC workload identity (no long-lived keys).
identity_token "aws" {
  audience = ["aws.workload.identity"]
}

# --- VARIABLE SET: SECRETS ---
# Links to an HCP Terraform variable set containing sensitive values.
# Create a variable set in HCP Terraform with a "db_password" variable,
# then replace the ID below with the actual variable set ID.
store "varset" "secrets" {
  id       = "REPLACE_WITH_VARSET_ID"
  category = "terraform"
}

# --- AUTO-APPROVE ORCHESTRATION RULE ---
# Block auto-approval if plan contains errors or any resource deletions.
# All destructive changes require manual review by an authorised Encircle operator.
deployment_auto_approve "safe_changes" {
  check {
    condition = context.plan.applyable
    reason    = "Plan is not in an applyable state (errors occurred)."
  }

  check {
    condition = context.plan.changes.remove == 0
    reason    = "Plan contains ${context.plan.changes.remove} resource deletion(s). Manual review required per Encircle change management policy."
  }
}

deployment_group "sandbox_group" {
  auto_approve_checks = [
    deployment_auto_approve.safe_changes
  ]
}

deployment_group "production_blue_group" {
  auto_approve_checks = [
    deployment_auto_approve.safe_changes
  ]
}

deployment_group "production_green_group" {
  auto_approve_checks = [
    deployment_auto_approve.safe_changes
  ]
}

# --- SANDBOX / DEVELOPMENT ---
# Encircle development environment. Reduced spec; not Multi-AZ.
# HLD §5.11.1 - for feature development and integration testing.
deployment "sandbox" {
  deployment_group = deployment_group.sandbox_group
  inputs = {
    region         = "eu-west-2"
    aws_account_id = "735910966814"
    environment    = "sandbox"
    role_arn       = "arn:aws:iam::735910966814:role/hcp-terraform-stack-role"
    identity_token = identity_token.aws.jwt

    bastion_key_name  = "ped-bastion-sandbox"
    encircle_vpn_cidr = "35.176.38.251/32" # Encircle VPN egress IP
    db_password       = store.varset.secrets.db_password

    # Cloudflare published IPv4 ranges - https://www.cloudflare.com/ips-v4
    cloudflare_ip_ranges = [
      "173.245.48.0/20",
      "103.21.244.0/22",
      "103.22.200.0/22",
      "103.31.4.0/22",
      "141.101.64.0/18",
      "108.162.192.0/18",
      "190.93.240.0/20",
      "188.114.96.0/20",
      "197.234.240.0/22",
      "198.41.128.0/17",
      "162.158.0.0/15",
      "104.16.0.0/13",
      "104.24.0.0/14",
      "172.64.0.0/13",
      "131.0.72.0/22"
    ]
    ops_alert_email = "ops@encircle.co.uk"
  }
}

# --- PRODUCTION: BLUE (Live environment) ---
# The active production environment serving all user traffic via Cloudflare.
# HLD §5.3 - Blue is the live environment until a deployment flip is executed.
deployment "production-blue" {
  deployment_group = deployment_group.production_blue_group
  inputs = {
    region         = "eu-west-2"
    aws_account_id = "735910966814"
    environment    = "production-blue"
    role_arn       = "arn:aws:iam::735910966814:role/hcp-terraform-stack-role"
    identity_token = identity_token.aws.jwt

    bastion_key_name  = "ped-bastion-prod"
    encircle_vpn_cidr = "35.176.38.251/32"
    db_password       = store.varset.secrets.db_password

    cloudflare_ip_ranges = [
      "173.245.48.0/20",
      "103.21.244.0/22",
      "103.22.200.0/22",
      "103.31.4.0/22",
      "141.101.64.0/18",
      "108.162.192.0/18",
      "190.93.240.0/20",
      "188.114.96.0/20",
      "197.234.240.0/22",
      "198.41.128.0/17",
      "162.158.0.0/15",
      "104.16.0.0/13",
      "104.24.0.0/14",
      "172.64.0.0/13",
      "131.0.72.0/22"
    ]
    ops_alert_email = "ops@encircle.co.uk"
  }
}

# --- PRODUCTION: GREEN (Deployment target / standby) ---
# The standby environment. Code is deployed here, smoke-tested, then traffic
# is flipped via Cloudflare within a 30-minute window (HLD §5.3.2 / §5.11.3.1).
# After a successful flip, Green becomes live and Blue becomes standby.
deployment "production-green" {
  deployment_group = deployment_group.production_green_group
  inputs = {
    region         = "eu-west-2"
    aws_account_id = "735910966814"
    environment    = "production-green"
    role_arn       = "arn:aws:iam::735910966814:role/hcp-terraform-stack-role"
    identity_token = identity_token.aws.jwt

    bastion_key_name  = "ped-bastion-prod"
    encircle_vpn_cidr = "35.176.38.251/32"
    db_password       = store.varset.secrets.db_password

    cloudflare_ip_ranges = [
      "173.245.48.0/20",
      "103.21.244.0/22",
      "103.22.200.0/22",
      "103.31.4.0/22",
      "141.101.64.0/18",
      "108.162.192.0/18",
      "190.93.240.0/20",
      "188.114.96.0/20",
      "197.234.240.0/22",
      "198.41.128.0/17",
      "162.158.0.0/15",
      "104.16.0.0/13",
      "104.24.0.0/14",
      "172.64.0.0/13",
      "131.0.72.0/22"
    ]
    ops_alert_email = "ops@encircle.co.uk"
  }
}
