#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "14 - Troubleshooting Helper"
echo "=================================================="
echo "1) AWS/ECR auth error in a script"
echo "2) Pods stuck in ImagePullBackOff"
echo "3) Pods stuck in Pending"
echo "4) ArgoCD Application OutOfSync"
echo "5) ArgoCD Application ComparisonError / path does not exist"
echo "6) kubeadm init failed"
echo "7) Cannot access ArgoCD UI"
echo "8) exec format error in pod logs"
echo "9) Print all pod / node / application status (general dump)"
read -rp "Pick a number (1-9): " choice

case "${choice}" in
  1)
    echo "Fix: re-run 'aws configure' then 'aws sts get-caller-identity'."
    echo "Once that succeeds, re-run whichever script failed."
    ;;
  2)
    echo "Fix: the ecr-regcred pull secret is missing in that namespace."
    echo "Re-run: bash 09-run-deploy-production-script.sh"
    ;;
  3)
    read -rp "Which pod name? " podname
    read -rp "Which namespace? " ns
    kubectl describe pod "${podname}" -n "${ns}" | tail -30
    echo "Look at the Events section above for the exact reason."
    ;;
  4)
    read -rp "Which application name? " appname
    kubectl annotate application "${appname}" -n argocd \
      argocd.argoproj.io/refresh=hard --overwrite
    echo "Hard refresh triggered for ${appname}."
    ;;
  5)
    echo "If it's one of the 14 app-tier services (auth/cockpit/messenger/"
    echo "social/task/vault/workflow + workers): expected, see 13-known-limitations.sh."
    echo "If it's an INFRA-tier app instead, that's unexpected - run:"
    read -rp "  Application name to describe: " appname
    kubectl describe application "${appname}" -n argocd
    ;;
  6)
    echo "Checking common causes..."
    free -h
    systemctl status containerd --no-pager || true
    echo "If a previous partial cluster exists, run: sudo kubeadm reset"
    ;;
  7)
    echo "Confirm you're using the SSH tunnel from 11-access-argocd-ui.sh,"
    echo "not a public port. Confirm 'kubectl port-forward' is still running"
    echo "in its own terminal on the VM - it stops if that session closes."
    ;;
  8)
    echo "'exec format error' = wrong CPU architecture image (amd64 on ARM,"
    echo "or vice versa). Needs a matching-architecture image build -"
    echo "not fixable from the cluster side."
    ;;
  9)
    echo "--- Nodes ---"; kubectl get nodes
    echo "--- Pods (all namespaces) ---"; kubectl get pods -A
    echo "--- Applications ---"; kubectl get applications -n argocd
    ;;
  *)
    echo "Not a valid option."
    ;;
esac
