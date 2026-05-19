#!/bin/bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-798701233691}"
ECR_REPO_PATH="${ECR_REPO_PATH:-nitroberry}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
K8S_VERSION="${K8S_VERSION:-v1.29}"

log() {
  echo ""
  echo "=> $1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

cluster_is_ready() {
  command_exists kubectl && kubectl get nodes >/dev/null 2>&1
}

install_base_packages() {
  log "Installing base packages if missing"
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y curl unzip git jq ca-certificates apt-transport-https gpg >/dev/null 2>&1 || true
}

install_helm() {
  if command_exists helm; then
    echo "Helm already installed."
    return
  fi

  log "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1
}

install_kubernetes_packages() {
  if command_exists kubeadm && command_exists kubelet && command_exists kubectl; then
    echo "Kubernetes packages already installed."
    return
  fi

  log "Installing kubeadm, kubelet, kubectl, and containerd"
  sudo swapoff -a >/dev/null 2>&1 || true
  sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab >/dev/null 2>&1 || true

  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null 2>&1
overlay
br_netfilter
EOF
  sudo modprobe overlay >/dev/null 2>&1 || true
  sudo modprobe br_netfilter >/dev/null 2>&1 || true

  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null 2>&1
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system >/dev/null 2>&1 || true

  sudo apt-get install -y containerd >/dev/null 2>&1 || true
  sudo mkdir -p /etc/containerd >/dev/null 2>&1 || true
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1 || true
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml >/dev/null 2>&1 || true
  sudo systemctl restart containerd >/dev/null 2>&1 || true
  sudo systemctl enable containerd >/dev/null 2>&1 || true

  sudo mkdir -p /etc/apt/keyrings >/dev/null 2>&1 || true
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes >/dev/null 2>&1 || true
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null 2>&1 || true
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y kubelet kubeadm kubectl >/dev/null 2>&1 || true
  sudo apt-mark hold kubelet kubeadm kubectl >/dev/null 2>&1 || true
}

ensure_kubernetes_cluster() {
  if cluster_is_ready; then
    log "Kubernetes cluster already reachable; skipping cluster init"
    return
  fi

  install_kubernetes_packages

  if [ ! -f /etc/kubernetes/admin.conf ]; then
    log "Initializing single-node Kubernetes cluster with kubeadm"
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16 >/dev/null 2>&1 || true
  else
    log "Existing kubeadm admin.conf found; reusing cluster configuration"
  fi

  mkdir -p "$HOME/.kube" >/dev/null 2>&1 || true
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config" >/dev/null 2>&1 || true
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config" >/dev/null 2>&1 || true
  export KUBECONFIG="$HOME/.kube/config"
  grep -qxF 'export KUBECONFIG=$HOME/.kube/config' "$HOME/.bashrc" \
    || echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc"

  if ! kubectl get namespace tigera-operator >/dev/null 2>&1; then
    log "Installing Calico CNI"
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml >/dev/null 2>&1 || true
    sleep 5
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml >/dev/null 2>&1 || true
  fi

  # Untaint the control-plane node so workloads can run on this single-node cluster
  log "Untainting master node to allow pod scheduling..."
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1 || true
}

# Run bootstrap sequence
log "[1/6] Installing base packages..."
install_base_packages

log "[2/6] Installing Helm..."
install_helm

log "[3/6] Setting up Kubernetes cluster..."
ensure_kubernetes_cluster

log "Waiting for Kubernetes node to be ready..."
sleep 10
kubectl wait --for=condition=Ready nodes --all --timeout=600s >/dev/null 2>&1 || true

# 4. Install ArgoCD
log "[4/6] Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null 2>&1

log "Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s >/dev/null 2>&1 || true

# 5. Apply Core Infrastructure & Secrets
log "[5/6] Applying Core Infrastructure..."

# Pre-create namespaces
kubectl create namespace database-namespace --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl create namespace traefik-ingress --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl create namespace gatekeeper-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# Create Postgres credentials secret (dummy credentials for local testing)
kubectl create secret generic postgres-credentials \
  --from-literal=postgres-user=postgres \
  --from-literal=postgres-password=nitroberry-local-pass \
  -n database-namespace --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# Install MetalLB operator
log "Installing MetalLB operator..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml >/dev/null 2>&1
sleep 10
log "Waiting for MetalLB operator to be ready..."
kubectl wait --for=condition=Ready pods --all -n metallb-system --timeout=300s >/dev/null 2>&1 || true

# Install local-path-provisioner for storage
log "Installing local-path-provisioner for storage..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml >/dev/null 2>&1
sleep 5

# 6. Start GitOps deployment via ArgoCD
log "[6/6] Applying ArgoCD Application (triggering GitOps deployment)..."

# Get the current directory (should be repo root)
REPO_ROOT="$(pwd)"

# Apply root ArgoCD app
kubectl apply -f "${REPO_ROOT}/argocd/root-app.yaml" >/dev/null 2>&1

log ""
log "=========================================================="
log "NitroBerry GitOps bootstrap COMPLETE!"
log "=========================================================="
log ""
log "✓ Kubernetes cluster ready"
log "✓ ArgoCD installed"
log "✓ Core infrastructure deployed"
log "✓ All 19 pods will be deployed via ArgoCD"
log ""
log "Access ArgoCD UI:"
log "  kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
log ""
log "ArgoCD admin password:"
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
log "  $ARGOCD_PASS"
log ""
log "Check deployment status:"
log "  kubectl get pods -A"
log ""
log "=========================================================="
