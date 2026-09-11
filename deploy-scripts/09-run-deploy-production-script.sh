#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "09 - Run deploy-production.sh"
echo "=================================================="

set -a
source "${SCRIPT_DIR}/00-config.env"
set +a

if [ ! -d "${REPO_DIR}/.git" ]; then
  echo "ERROR: repo not found at ${REPO_DIR}. Run 05-clone-repository.sh first."
  exit 1
fi

cd "${REPO_DIR}"

bash script/deploy-production.sh

echo
echo "=================================================="
echo "deploy-production.sh finished."
echo "The success banner above prints regardless of per-app sync status —"
echo "always follow up with 10-verify-argocd-application-sync.sh."
echo "=================================================="
echo
echo "Next: bash 10-verify-argocd-application-sync.sh"
