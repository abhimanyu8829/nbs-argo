#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.env"

echo "=================================================="
echo "11 - Access ArgoCD UI (Safely, via SSH tunnel)"
echo "=================================================="

echo "Fetching ArgoCD admin password..."
ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '')"

if [ -z "${ARGOCD_PASSWORD}" ]; then
  echo "Could not fetch the initial admin password (it may already have been rotated)."
else
  echo "ArgoCD admin password: ${ARGOCD_PASSWORD}"
fi

echo
echo "--- On THIS machine (the OCI VM), run this in a dedicated terminal: ---"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo
echo "--- On your LOCAL machine, in a separate terminal, run: ---"
echo "  ssh -i ${SSH_KEY_PATH} -L 8080:localhost:8080 ubuntu@${OCI_PUBLIC_IP}"
echo
echo "--- Then open in your browser: ---"
echo "  https://localhost:8080"
echo "  (username: admin / password: printed above)"
echo
echo "A self-signed cert warning is expected - click through it."
echo
echo "IMPORTANT: change the admin password after first login"
echo "  (UI: User Info -> Update Password, or: argocd account update-password)"
echo
echo "This script does not start the port-forward for you automatically,"
echo "since it needs to stay in the foreground of its own terminal."
echo "Run the kubectl port-forward command above directly when ready."
echo
echo "Next: bash 12-access-services-port-forward.sh"
