PPE Certification Platform - HCP Terraform Stack
HLD-PPE-2026-001 | eu-west-2 (London)
Classification: OFFICIAL-SENSITIVE

=== BEFORE YOU BEGIN ===

1. Replace all placeholder values in deployments.tfdeploy.hcl (and ensure aws_account_id is set):
   - YOUR_ACCOUNT_ID   → AWS account ID (also set aws_account_id input per deployment)
   - YOUR_HCP_ORG_NAME → HCP Terraform organisation name
   - YOUR_VPN_EGRESS_IP → Encircle VPN egress IP (used to restrict bastion SSH)
   - ami-XXXXXXXXXXXXXXXXX → ARM64 (Graviton) AMI ID for eu-west-2

2. Replace YOUR_ACCOUNT_ID and YOUR_HCP_ORG_NAME in oidc-policy.json,
   then attach the policy to the hcp-terraform-stack-role IAM role.

3. Set db_password as a SENSITIVE variable in your HCP Terraform variable set.
   Never commit this value to source control.

4. Ensure Cloudflare IP ranges in deployments.tfdeploy.hcl are current:
   https://www.cloudflare.com/ips-v4

=== QUICK EXECUTION COMMANDS ===

# Initialise the stack
terraform stacks init

# Sandbox (development)
terraform stacks plan  -deployment=sandbox
terraform stacks apply -deployment=sandbox

# Production - Blue (live environment)
terraform stacks plan  -deployment=production-blue
terraform stacks apply -deployment=production-blue

# Production - Green (deployment target / standby)
terraform stacks plan  -deployment=production-green
terraform stacks apply -deployment=production-green

=== DEPLOYMENT (BLUE/GREEN FLIP) ===

See HLD-PPE-2026-001 §5.3.2 and §5.11.3.1 for the full flip procedure.
Traffic routing between Blue and Green is controlled via Cloudflare origin settings,
not by re-applying this stack. The stack manages infrastructure parity between
both environments.

Auto-approve is blocked if the plan contains any resource deletions.
All destructive changes require manual operator review.

=== HCP STACK SYNC: PROVIDER LOCKFILE ===

If HCP Stack sync fails with a ".terraform.lock.hcl" / provider checksum error, generate a
multi-platform lockfile and commit it:

  ./generate-lockfile.sh

This produces .terraform.lock.hcl containing checksums for the HCP runner platform (linux_amd64)
as well as common developer platforms (macOS/windows). Commit the resulting lockfile, then re-sync.


=== HCP SETUP (ORG/PROJECT) ===

This package is prepared for:
  - HCP Terraform org: ayazi-ped
  - HCP Terraform project: ped-demo

oidc-policy.json is scoped to allow deployments from ANY stack in that project.
