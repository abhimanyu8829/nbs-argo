#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "07 - Run setup-vm.sh (Bootstrap)"
echo "=================================================="
echo "This takes 15-25 minutes. Do not interrupt it."
echo

set -a
source "${SCRIPT_DIR}/00-config.env"
set +a

if [[ "${POSTGRES_PASSWORD}" == "CHANGE-ME-TO-A-REAL-PASSWORD" ]]; then
  echo "ERROR: POSTGRES_PASSWORD still has the placeholder value."
  echo "Edit 00-config.env first, then re-run this script."
  exit 1
fi

if [ ! -d "${REPO_DIR}/.git" ]; then
  echo "ERROR: repo not found at ${REPO_DIR}. Run 05-clone-repository.sh first."
  exit 1
fi

cd "${REPO_DIR}"

echo "Using: script/installation/setup-vm.sh (the ARM-aware, current version)."
echo "NOT the stale duplicate 'setup-vm.sh' at the repo root — that one is skipped."
echo

bash script/installation/setup-vm.sh

echo
echo "=================================================="
echo "setup-vm.sh finished."
echo "Copy the ArgoCD admin password printed above somewhere safe."
echo "=================================================="
echo
echo "Next: bash 08-verify-cluster-and-argocd.sh"
