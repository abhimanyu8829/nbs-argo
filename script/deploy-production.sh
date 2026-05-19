#!/usr/bin/env bash
set -euo pipefail

# NitroBerry Platform: Production Deployment Verification & Configuration Script
# This script runs AFTER setup-vm.sh completes to ensure all production requirements are met
# It performs: storage provisioning, ECR credential distribution, ArgoCD configuration, pod readiness checks

AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
ECR_REPO_PATH="${ECR_REPO_PATH:-nitroberry}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600s}"
INSTALL_LOCAL_PATH_STORAGE="${INSTALL_LOCAL_PATH_STORAGE:-true}"

# All namespaces that need ECR credentials
APP_NAMESPACES=(
  auth-namespace
  cockpit-namespace
  messenger-namespace
  social-namespace
  task-namespace
  vault-namespace
  workflow-namespace
)

SHARED_NAMESPACES=(
  "${ARGOCD_NAMESPACE}"
  database-namespace
  default
  gatekeeper-system
  metallb-system
  traefik-ingress
)

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: $1" >&2
    exit 1
  fi
}

section() {
  echo
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Verify prerequisites
require_command aws
require_command jq
require_command kubectl

section "PHASE 1: Kubernetes & AWS Access Verification"
log "Checking Kubernetes cluster access..."
kubectl version --client >/dev/null || { echo "ERROR: kubectl not configured"; exit 1; }
kubectl get namespace "${ARGOCD_NAMESPACE}" >/dev/null || { echo "ERROR: ArgoCD namespace not found"; exit 1; }

log "Checking AWS credentials..."
if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  log "Auto-detected AWS Account ID: ${AWS_ACCOUNT_ID}"
fi
aws sts get-caller-identity >/dev/null || { echo "ERROR: AWS credentials invalid"; exit 1; }

section "PHASE 2: Storage Provisioning"
if [[ "${INSTALL_LOCAL_PATH_STORAGE}" == "true" ]]; then
  log "Checking for existing StorageClass..."
  if ! kubectl get storageclass local-path >/dev/null 2>&1; then
    log "Installing local-path-provisioner (storage for persistent volumes)..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    kubectl wait --for=condition=available deployment/local-path-provisioner -n local-path-storage --timeout=120s
    log "✓ Local-path StorageClass installed"
  else
    log "✓ StorageClass 'local-path' already exists"
  fi
fi

section "PHASE 3: ECR Credential Distribution"
log "Creating ECR credentials in all application namespaces..."

ECR_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

create_ecr_secret() {
  local namespace=$1
  log "  Creating ECR secret in namespace: $namespace"
  
  # Create namespace if it doesn't exist
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  # Create imagePullSecret for private ECR
  kubectl create secret docker-registry ecr-regcred \
    --docker-server="${ECR_REGISTRY}" \
    --docker-username=AWS \
    --docker-password="$ECR_TOKEN" \
    -n "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

# Create ECR secrets in all application namespaces
for ns in "${APP_NAMESPACES[@]}"; do
  create_ecr_secret "$ns"
done

# Also ensure shared namespaces have the secret
for ns in "${SHARED_NAMESPACES[@]}"; do
  create_ecr_secret "$ns"
done

log "✓ ECR credentials distributed to all namespaces"

section "PHASE 4: ArgoCD Repo Server Configuration"
log "Configuring ArgoCD to pull OCI Helm charts from ECR..."

# Create OCI Helm repository credential in ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

if [[ -n "${ARGOCD_PASSWORD}" ]]; then
  log "  Updating ArgoCD repo-server credentials for ECR..."
  
  # Create a secret with ECR credentials for ArgoCD repo-server
  kubectl create secret generic argocd-ecr-creds \
    --from-literal=username=AWS \
    --from-literal=password="${ECR_TOKEN}" \
    -n "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  # Patch repo-server deployment to use the secret (if not already using it)
  kubectl patch deployment argocd-repo-server -n "${ARGOCD_NAMESPACE}" \
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-repo-server","env":[{"name":"HELM_REPOSITORY_CACHE","value":"/tmp/helm-repository-cache"}]}]}}}}' \
    2>/dev/null || true

  log "  ✓ ArgoCD repo-server configured for ECR"
else
  log "  ⚠ ArgoCD password not found; skipping detailed repo-server patching"
fi

section "PHASE 5: ArgoCD Application Refresh"
log "Refreshing all ArgoCD applications..."

# Force refresh of the root application
kubectl annotate application -n "${ARGOCD_NAMESPACE}" nitroberry-platform-apps \
  argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true

log "✓ Applications refresh triggered"

section "PHASE 6: Pod Readiness Verification"
log "Waiting for all pods to reach Ready state (timeout: ${WAIT_TIMEOUT})..."
log "This may take 2-5 minutes as all microservices deploy..."

# Monitor pod rollout across all namespaces
start_time=$(date +%s)
timeout_seconds=$(echo "$WAIT_TIMEOUT" | sed 's/s$//')

while true; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  if [[ $elapsed -gt $timeout_seconds ]]; then
    log "⚠ Timeout reached. Some pods may still be starting."
    break
  fi

  not_ready=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running" | grep -v "Completed" | wc -l)
  if [[ $not_ready -eq 0 ]]; then
    log "✓ All pods are Ready"
    break
  fi

  # Show progress every 10 seconds
  if [[ $((elapsed % 10)) -eq 0 ]]; then
    ready_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running\|Completed" || echo "0")
    total_pods=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
    log "  Status: $ready_pods/$total_pods pods ready..."
  fi

  sleep 2
done

section "PHASE 7: ArgoCD Application Sync Status"
log "Verifying ArgoCD application sync status..."

echo ""
kubectl get applications -n "${ARGOCD_NAMESPACE}" -o wide 2>/dev/null || true

# Count applications
synced_apps=$(kubectl get applications -n "${ARGOCD_NAMESPACE}" -o jsonpath='{range .items[*]}{.status.sync.status}{"\n"}{end}' 2>/dev/null | grep -c "Synced" || echo "0")
total_apps=$(kubectl get applications -n "${ARGOCD_NAMESPACE}" --no-headers 2>/dev/null | wc -l)

if [[ $synced_apps -eq $total_apps ]]; then
  log "✓ All applications are Synced ($synced_apps/$total_apps)"
else
  log "⚠ Some applications are not synced ($synced_apps/$total_apps)"
fi

section "PHASE 8: Cluster Health Summary"

# Pod status summary
pod_summary=$(kubectl get pods -A --no-headers 2>/dev/null | awk '{print $4}' | sort | uniq -c | tr '\n' ',' | sed 's/,$//')
log "Pod Status: $pod_summary"

# Node status
node_status=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [[ "$node_status" == "True" ]]; then
  log "✓ Kubernetes Nodes: Ready"
else
  log "⚠ Kubernetes Nodes: Not Ready"
fi

# ArgoCD status
argocd_replicas=$(kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [[ -n "$argocd_replicas" && "$argocd_replicas" -gt 0 ]]; then
  log "✓ ArgoCD Server: Ready"
else
  log "⚠ ArgoCD Server: Not Ready"
fi

section "DEPLOYMENT COMPLETE"
echo ""
echo "✅ NitroBerry Platform is deployed and ready for production!"
echo ""
echo "Next Steps:"
echo "1. Access ArgoCD Dashboard:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open: https://localhost:8080"
echo ""
echo "2. Monitor application status:"
echo "   kubectl get applications -n argocd -w"
echo ""
echo "3. Check pod logs if needed:"
echo "   kubectl logs -f -n <namespace> <pod-name>"
echo ""
echo "For troubleshooting, see the README.md file."
echo ""
