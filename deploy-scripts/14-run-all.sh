#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STEPS=(
  "01-verify-vm-architecture.sh"
  "02-install-base-packages.sh"
  "03-install-aws-cli.sh"
  "04-configure-aws-credentials.sh"
  "05-clone-repository.sh"
  "06-set-environment-variables.sh"
  "07-run-setup-vm-script.sh"
  "08-verify-cluster-and-argocd.sh"
  "09-run-deploy-production-script.sh"
  "10-verify-argocd-application-sync.sh"
)

echo "=================================================="
echo "15 - Run All Steps (01 through 10, in order)"
echo "=================================================="
echo "Steps 11 and 12 (ArgoCD UI / port-forwards) are left out of this"
echo "master run since they start long-lived foreground/background"
echo "processes - run those two manually when you're ready."
echo
echo "Edit 00-config.env now if you haven't already."
read -rp "Press Enter once 00-config.env is edited, or Ctrl+C to stop: " _

for step in "${STEPS[@]}"; do
  echo
  echo ">>> Running ${step}"
  bash "${SCRIPT_DIR}/${step}"
  read -rp ">>> ${step} done. Press Enter to continue to the next step (Ctrl+C to stop here): " _
done

echo
echo "=================================================="
echo "All automated steps complete."
echo "Run these manually next:"
echo "  bash 11-access-argocd-ui.sh"
echo "  bash 12-access-services-port-forward.sh"
echo "For known gaps in this repo, run: bash 13-known-limitations.sh"
echo "=================================================="
