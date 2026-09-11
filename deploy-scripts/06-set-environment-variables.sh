#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "06 - Validate Environment Variables"
echo "=================================================="
echo "Note: scripts 07 and 09 load 00-config.env automatically."
echo "This step just checks the values before the long bootstrap runs."
echo

set -a
source "${SCRIPT_DIR}/00-config.env"
set +a

echo "AWS_REGION        = ${AWS_REGION}"
echo "POSTGRES_PASSWORD = ${POSTGRES_PASSWORD}"
echo "REPO_DIR          = ${REPO_DIR}"
echo "AZURE_CLIENT_ID   = ${AZURE_CLIENT_ID:-<not set - Azure Key Vault step will be skipped>}"

if [[ "${POSTGRES_PASSWORD}" == "CHANGE-ME-TO-A-REAL-PASSWORD" ]]; then
  echo
  echo "ERROR: You have not changed POSTGRES_PASSWORD in 00-config.env."
  echo "Edit that file and set a real password before continuing."
  exit 1
fi

echo
echo "Checklist:"
echo "  [x] AWS_REGION set"
echo "  [x] POSTGRES_PASSWORD changed from placeholder"
echo
echo "Next: bash 07-run-setup-vm-script.sh"
