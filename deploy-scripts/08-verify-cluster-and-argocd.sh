#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.env"

echo "=================================================="
echo "08 - Verify Cluster & ArgoCD"
echo "=================================================="

echo "--- Nodes ---"
kubectl get nodes

echo
echo "--- ArgoCD pods ---"
kubectl get pods -n argocd

echo
echo "--- MetalLB pods ---"
kubectl get pods -n metallb-system

echo
echo "--- Calico pods ---"
kubectl get pods -n kube-system | grep -i calico || echo "No calico pods found - check this."

echo
echo "--- ECR account substitution check ---"
if [ -f "${REPO_DIR}/argocd/root-app.yaml" ]; then
  grep -A1 "ecrRepoUrl" "${REPO_DIR}/argocd/root-app.yaml" || true
  if grep -q "798701233691" "${REPO_DIR}/argocd/root-app.yaml"; then
    echo "WARNING: root-app.yaml still shows the placeholder account 798701233691."
    echo "The auto-substitution in setup-vm.sh may not have run correctly."
  else
    echo "OK: placeholder account ID has been replaced."
  fi
else
  echo "WARNING: could not find ${REPO_DIR}/argocd/root-app.yaml"
fi

echo
echo "Checklist:"
echo "  [ ] Node shows Ready"
echo "  [ ] ArgoCD pods all Running"
echo "  [ ] MetalLB pods Running"
echo "  [ ] Calico pods Running"
echo "  [ ] root-app.yaml shows your account, not the placeholder"
echo
echo "Next: bash 09-run-deploy-production-script.sh"
