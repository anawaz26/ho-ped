# ============================================================
# PPE Certification Platform - HCP Terraform Stack Deployments
# HLD-PPE-2026-001 | Blue/Green model (HLD §5.3.1 / §5.11.3)
# ============================================================

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


deployment_group "safe_changes_group" {
  auto_approve_checks = [
    deployment_auto_approve.safe_changes
  ]
}


# --- SANDBOX / DEVELOPMENT ---
# Encircle development environment. Reduced spec; not Multi-AZ.
# HLD §5.11.1 - for feature development and integration testing.
deployment "sandbox" {
  deployment_group = deployment_group.safe_changes_group
  inputs = {
    region     = "eu-west-2"

    aws_account_id = "735910966814"
    environment = "sandbox"
    role_arn   = "arn:aws:iam::${var.aws_account_id}:role/hcp-terraform-stack-role"

    bastion_key_name     = "ped-bastion-sandbox"
    encircle_vpn_cidr    = "35.176.38.251/32" # Encircle VPN egress IP
    db_password          = var.db_password           # Sourced from HCP Terraform variable set (sensitive)

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
  deployment_group = deployment_group.safe_changes_group
  inputs = {
    region      = "eu-west-2"

    aws_account_id = "735910966814"
    environment = "production-blue"
    role_arn   = "arn:aws:iam::${var.aws_account_id}:role/hcp-terraform-stack-role"

    bastion_key_name     = "ped-bastion-prod"
    encircle_vpn_cidr    = "35.176.38.251/32"
    db_password          = var.db_password

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
  deployment_group = deployment_group.safe_changes_group
  inputs = {
    region      = "eu-west-2"

    aws_account_id = "735910966814"
    environment = "production-green"
    role_arn   = "arn:aws:iam::${var.aws_account_id}:role/hcp-terraform-stack-role"

    bastion_key_name     = "ped-bastion-prod"
    encircle_vpn_cidr    = "35.176.38.251/32"
    db_password          = var.db_password

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
