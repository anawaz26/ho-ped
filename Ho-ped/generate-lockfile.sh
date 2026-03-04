#!/usr/bin/env bash
set -euo pipefail

# Generate a multi-platform provider lockfile for HCP Terraform Stacks.
# Run this from the stack root (the folder containing *.tfstack.hcl files).

terraform version

# This command writes/updates .terraform.lock.hcl with checksums for the listed platforms.
terraform stacks providers-lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64 \
  -platform=darwin_amd64 \
  -platform=windows_amd64

echo "✅ Wrote .terraform.lock.hcl with multi-platform checksums. Commit it, then re-sync the stack."
