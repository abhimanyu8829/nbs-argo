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
echo "--- Flannel pods ---"
kubectl get pods -n kube-flannel || echo "No flannel pods found - check this."

echo
echo "--- ECR account substitution check ---"
if [ -f "${REPO_DIR}/argocd/root-app.yaml" ]; then
  grep -A1 "ecrRepoUrl" "${REPO_DIR}/argocd/root-app.yaml" || true
  if grep -q "798701233691" "${REPO_DIR}/argocd/root-app.yaml"; then
    echo "NOTE: root-app.yaml shows account 798701233691."
    echo "This is expected if 798701233691 IS your actual AWS account - the"
    echo "substitution replaces the placeholder with your detected account,"
    echo "and if they're numerically the same, the file looks unchanged."
    echo "Confirm your real account with: aws sts get-caller-identity"
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
echo "  [ ] Flannel pods Running"
echo "  [ ] root-app.yaml shows your account (see note above if it matches the placeholder numerically)"
echo
echo "Next: bash 09-run-deploy-production-script.sh"
