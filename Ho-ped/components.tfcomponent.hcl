# ============================================================
# PPE Certification Platform - Stack Component Definitions (GA)
# Converted from beta .tfstack.hcl to GA .tfcomponent.hcl format.
#
# This Stack defines a single component that sources a local Terraform module
# (./modules/ped) containing the AWS resources/data sources.
# ============================================================

component "ped" {
  source = "./modules/ped"

  providers = {
    aws = provider.aws.this
  }

  inputs = {
    aws_account_id = var.aws_account_id
    region = var.region
    environment = var.environment
    role_arn = var.role_arn
    bastion_key_name = var.bastion_key_name
    encircle_vpn_cidr = var.encircle_vpn_cidr
    cloudflare_ip_ranges = var.cloudflare_ip_ranges
    db_password = var.db_password
    ops_alert_email = var.ops_alert_email
  }
}
