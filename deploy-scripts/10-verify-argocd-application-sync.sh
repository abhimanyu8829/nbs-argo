#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "10 - Verify ArgoCD Application Sync Status"
echo "=================================================="

echo "--- All applications ---"
kubectl get applications -n argocd

INFRA_APPS=(metallb postgres redis pgbouncer traefik opa-gatekeeper external-secrets external-secrets-config reloader)
APP_TIER=(auth-api auth-worker cockpit-api cockpit-worker messenger-api social-api social-worker task-api task-worker vault-api vault-worker workflow-api workflow-worker)

echo
echo "--- Expected: infra-tier apps should be Synced/Healthy ---"
for app in "${INFRA_APPS[@]}"; do
  status="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo 'NOT FOUND')"
  echo "  ${app}: ${status}"
done

echo
echo "--- Expected: app-tier apps will likely show errors (missing chart source - see known limitations) ---"
for app in "${APP_TIER[@]}"; do
  status="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo 'NOT FOUND')"
  echo "  ${app}: ${status}"
done

echo
echo "--- Pod status across all namespaces ---"
kubectl get pods -A

echo
echo "If an INFRA-tier app above is not Synced/Healthy, investigate with:"
echo "  kubectl describe application <app-name> -n argocd"
echo
echo "If an APP-tier app shows an error, that matches this repo's known"
echo "limitation (see 13-known-limitations.sh) - not fixable from this repo alone."
echo
echo "Next: bash 11-access-argocd-ui.sh"
