#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "04 - Configure AWS Credentials"
echo "=================================================="
echo "You will be prompted for:"
echo "  - AWS Access Key ID"
echo "  - AWS Secret Access Key"
echo "  - Default region name  -> use ap-south-1"
echo "  - Default output format -> use json"
echo

aws configure

echo
echo "Verifying credentials..."
IDENTITY_JSON="$(aws sts get-caller-identity)"
echo "${IDENTITY_JSON}"

ACCOUNT_ID="$(echo "${IDENTITY_JSON}" | grep -o '"Account": *"[0-9]*"' | grep -o '[0-9]*')"

echo
echo "=================================================="
echo "CONFIRM: the Account above (${ACCOUNT_ID}) is the AWS account"
echo "you intend to deploy into. If it's wrong, re-run this script"
echo "with the correct IAM credentials before continuing."
echo "=================================================="
echo
echo "Checklist:"
echo "  [x] aws sts get-caller-identity returned without error"
echo "  [ ] YOU confirmed the Account ID is correct"
echo
echo "Next: bash 05-clone-repository.sh"
