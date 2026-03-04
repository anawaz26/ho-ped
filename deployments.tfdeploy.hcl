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

# --- SANDBOX / DEVELOPMENT ---
# Encircle development environment for trial deployment.
# HLD §5.11.1 - for feature development and integration testing.
deployment "sandbox" {
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

# --- PRODUCTION DEPLOYMENTS (commented out for trial) ---
# Uncomment when ready to deploy production environments.
# Note: deployment_group and deployment_auto_approve require
# HCP Terraform Premium. On the free tier, all plans require
# manual approval in the UI.

# deployment "production-blue" {
#   inputs = {
#     region         = "eu-west-2"
#     aws_account_id = "735910966814"
#     environment    = "production-blue"
#     role_arn       = "arn:aws:iam::735910966814:role/hcp-terraform-stack-role"
#     identity_token = identity_token.aws.jwt
#     bastion_key_name  = "ped-bastion-prod"
#     encircle_vpn_cidr = "35.176.38.251/32"
#     db_password       = store.varset.secrets.db_password
#     cloudflare_ip_ranges = [
#       "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22",
#       "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18",
#       "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22",
#       "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
#       "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"
#     ]
#     ops_alert_email = "ops@encircle.co.uk"
#   }
# }

# deployment "production-green" {
#   inputs = {
#     region         = "eu-west-2"
#     aws_account_id = "735910966814"
#     environment    = "production-green"
#     role_arn       = "arn:aws:iam::735910966814:role/hcp-terraform-stack-role"
#     identity_token = identity_token.aws.jwt
#     bastion_key_name  = "ped-bastion-prod"
#     encircle_vpn_cidr = "35.176.38.251/32"
#     db_password       = store.varset.secrets.db_password
#     cloudflare_ip_ranges = [
#       "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22",
#       "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18",
#       "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22",
#       "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
#       "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"
#     ]
#     ops_alert_email = "ops@encircle.co.uk"
#   }
# }
