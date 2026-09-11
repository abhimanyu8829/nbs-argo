#!/bin/bash
set -euo pipefail

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/dushyantajangid/NitroBerry-Platform.git}"
GIT_BRANCH="${GIT_BRANCH:-argocdTest}"
AWS_REGION_DEFAULT="${AWS_REGION_DEFAULT:-ap-south-1}"
AWS_REGION="${AWS_REGION:-$AWS_REGION_DEFAULT}"
K8S_VERSION="${K8S_VERSION:-v1.29}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

# ---------------------------------------------------------------------------
# Architecture detection
# Both "arm64" (Docker/macOS naming) and "aarch64" (Linux kernel naming) are
# the same physical architecture. We normalise to a single ARCH variable that
# downstream functions can branch on.
# ---------------------------------------------------------------------------
detect_arch() {
  local raw
  raw="$(uname -m)"
  case "$raw" in
    x86_64)           echo "x86_64" ;;
    arm64 | aarch64)  echo "arm64"  ;;
    *)
      echo "ERROR: Unsupported architecture: $raw" >&2
      exit 1
      ;;
  esac
}

ARCH="$(detect_arch)"

log() {
  echo ""
  echo "=> $1"
}

log "Detected system architecture: $(uname -m) → normalised as ${ARCH}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

cluster_is_ready() {
  command_exists kubectl && kubectl get nodes >/dev/null 2>&1
}

install_base_packages() {
  log "Installing base packages if missing"
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y curl unzip git jq ca-certificates apt-transport-https gpg >/dev/null
}

# ---------------------------------------------------------------------------
# AWS CLI — credentials come from `aws configure` (run before this script).
# AWS_ACCOUNT_ID is auto-detected at runtime via sts get-caller-identity.
# The only arch difference is the download URL.
# ---------------------------------------------------------------------------
install_aws_cli() {
  if command_exists aws; then
    echo "AWS CLI already installed."
    return
  fi

  log "Installing AWS CLI v2 (arch: ${ARCH})"

  if [[ "${ARCH}" == "arm64" ]]; then
    # arm64 / aarch64 — same binary, AWS names it "aarch64"
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
  else
    # x86_64
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  fi

  unzip -q awscliv2.zip
  sudo ./aws/install >/dev/null
  rm -rf aws awscliv2.zip
}

install_helm() {
  if command_exists helm; then
    echo "Helm already installed."
    return
  fi

  log "Installing Helm (official script handles arch automatically)"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

# ---------------------------------------------------------------------------
# Kubernetes packages
# The apt repository and packages are the same for both architectures —
# apt resolves the correct binary automatically. The one thing that differs
# is the containerd binary path check on arm64 OCI images (already handled
# by the distro package), so no manual branching is needed here beyond a
# clear log line confirming which arch is in use.
# ---------------------------------------------------------------------------
install_kubernetes_packages() {
  if command_exists kubeadm && command_exists kubelet && command_exists kubectl; then
    echo "Kubernetes packages already installed."
    return
  fi

  log "Installing kubeadm, kubelet, kubectl, and containerd (arch: ${ARCH})"
  sudo swapoff -a
  sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter

  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system >/dev/null

  # containerd — the apt package is multi-arch; apt picks the right binary
  sudo apt-get install -y containerd >/dev/null
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd >/dev/null

  # Kubernetes apt repo — arch-agnostic URL; apt resolves the right .deb
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y kubelet kubeadm kubectl >/dev/null
  sudo apt-mark hold kubelet kubeadm kubectl >/dev/null
}

ensure_kubernetes_cluster() {
  if cluster_is_ready; then
    log "Kubernetes cluster already reachable; skipping cluster install/init"
    return
  fi

  install_kubernetes_packages

  if [ ! -f /etc/kubernetes/admin.conf ]; then
    log "Initializing single-node Kubernetes cluster"
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16
  else
    log "Existing kubeadm admin.conf found; reusing cluster configuration"
  fi

  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  export KUBECONFIG="$HOME/.kube/config"
  grep -qxF 'export KUBECONFIG=$HOME/.kube/config' "$HOME/.bashrc" \
    || echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc"

  if ! kubectl get namespace tigera-operator >/dev/null 2>&1; then
    log "Installing Calico CNI"
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml
  fi

  # Untaint the control-plane node so workloads can run on this single-node cluster
  echo "=> Untainting master node to allow pod scheduling..."
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
}

wait_for_namespace() {
  local namespace="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-5}"

  log "Waiting for namespace ${namespace} to be created by ArgoCD"

  for _ in $(seq 1 "$attempts"); do
    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
      return
    fi
    sleep "$sleep_seconds"
  done

  echo "Namespace ${namespace} was not created in time. Check ArgoCD sync status before creating runtime secrets."
  exit 1
}

install_external_secrets_crds() {
  log "Preparing External Secrets CRDs"

  if [ -d "./helm/external-secrets" ]; then
    log "Pre-installing External Secrets CRDs"
    helm dependency build ./helm/external-secrets >/dev/null

    ESO_CHART_PACKAGE="$(find ./helm/external-secrets/charts -name 'external-secrets-*.tgz' | head -n 1)"
    if [ -z "$ESO_CHART_PACKAGE" ]; then
      echo "Could not find External Secrets dependency package under ./helm/external-secrets/charts."
      exit 1
    fi

    helm show crds "$ESO_CHART_PACKAGE" | kubectl apply -f -
    kubectl wait --for=condition=Established crd/clustersecretstores.external-secrets.io --timeout=120s
    kubectl wait --for=condition=Established crd/externalsecrets.external-secrets.io --timeout=120s
    kubectl wait --for=condition=Established crd/secretstores.external-secrets.io --timeout=120s
  fi
}

bootstrap_azure_service_principal_secret() {
  if [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ]; then
    echo "Skipping azure-secret-sp creation. Set AZURE_CLIENT_ID and AZURE_CLIENT_SECRET before running this script."
    return
  fi

  wait_for_namespace external-secrets

  kubectl create secret generic azure-secret-sp \
    --from-literal=ClientID="$AZURE_CLIENT_ID" \
    --from-literal=ClientSecret="$AZURE_CLIENT_SECRET" \
    -n external-secrets --dry-run=client -o yaml | kubectl apply -f -
  echo "Azure Service Principal credentials stored in Kubernetes secret external-secrets/azure-secret-sp."
}

bootstrap_postgres_credentials_secret() {
  if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Skipping postgres-credentials creation. Set POSTGRES_PASSWORD before running this script."
    return
  fi

  wait_for_namespace database-namespace

  kubectl create secret generic postgres-credentials \
    --from-literal=postgres-user="$POSTGRES_USER" \
    --from-literal=postgres-password="$POSTGRES_PASSWORD" \
    -n database-namespace --dry-run=client -o yaml | kubectl apply -f -
  echo "Postgres credentials stored in Kubernetes secret database-namespace/postgres-credentials."
}

# ---------------------------------------------------------------------------
# Bootstrap sequence
# AWS credentials are expected to already be configured via `aws configure`.
# AWS_ACCOUNT_ID is auto-detected below — no need to hardcode it.
# ---------------------------------------------------------------------------
install_base_packages
install_aws_cli
install_helm
ensure_kubernetes_cluster

echo "=> Waiting for Kubernetes node to be ready..."
sleep 10
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# 3. Use current repository
echo "=> [3/7] Using current NitroBerry repository..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(realpath "$SCRIPT_DIR/../..")"

cd "$REPO_ROOT"

# 4. Verify Existing ArgoCD Installation
echo "=> [4/7] Checking existing ArgoCD installation..."

if kubectl get namespace argocd >/dev/null 2>&1; then
    echo "ArgoCD already installed. Skipping installation."
else
    echo "Installing ArgoCD..."
    kubectl create namespace argocd
    kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "=> Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
fi

# Loosen argocd-repo-server's probe timeouts. The default 5s timeout is too
# tight in some environments and causes CrashLoopBackOff even when the
# process is healthy and the node has free resources. Safe to run every
# time (idempotent) — patches whether ArgoCD was just installed above or
# already existed from a previous run.
echo "=> Patching argocd-repo-server probe timeouts (avoids false-positive CrashLoopBackOff)..."
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":30},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":10},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":30},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":10}
]' || echo "Probe patch skipped (repo-server may not exist yet on a brand-new cluster — safe to ignore)."

echo "=> Waiting for argocd-repo-server to be ready after probe patch..."
kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=180s || true

# 5. ECR Login & ArgoCD Repo Configuration
# AWS_ACCOUNT_ID is auto-detected from the credentials set via `aws configure`
echo "=> [5/7] Configuring AWS ECR tokens and CronJob..."
AWS_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "    Using AWS Account: ${AWS_ACCOUNT_ID} | Region: ${AWS_REGION} | Arch: ${ARCH}"

kubectl create secret docker-registry ecr-regcred \
  --docker-server="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" \
  --docker-username=AWS \
  --docker-password="$AWS_TOKEN" \
  -n argocd --dry-run=client -o yaml | kubectl apply -f -

# Deploy the ECR helper to keep tokens fresh.
kubectl apply -f ./script/installation/ecr-helper.yaml

# 6. Apply Core Infrastructure
echo "=> [6/7] Applying Core Infrastructure prerequisites..."

# Install MetalLB operator explicitly (CRDs first, wait, then IP pool config is managed by helm)
echo "=> Installing MetalLB operator..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
echo "=> Waiting for MetalLB operator to be ready..."
kubectl wait --for=condition=Ready pods --all -n metallb-system --timeout=300s


# 7. Start GitOps deployment via ArgoCD
echo "=> [7/7] Applying ArgoCD Apps (Triggering GitOps deployment)..."

# Dynamically update the ECR URL in the root ArgoCD app to match the current AWS account and region.
sed -i "s/798701233691.dkr.ecr.ap-south-1.amazonaws.com/${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/g" ./argocd/root-app.yaml

kubectl apply -f ./argocd/root-app.yaml

echo "=> Bootstrapping runtime secrets after ArgoCD creates target namespaces..."
bootstrap_azure_service_principal_secret
bootstrap_postgres_credentials_secret

echo ""
echo "=========================================================="
echo "NitroBerry GitOps bootstrap complete."
echo "Architecture: ${ARCH} ($(uname -m))"
echo "ArgoCD is now configured to pull infrastructure Helm charts from ECR."
echo "Application API/worker charts are expected to live in their own app repos."
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo ""
echo "=========================================================="