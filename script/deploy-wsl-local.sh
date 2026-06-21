#!/bin/bash

set -Eeuo pipefail

###############################################################################
# CONFIG
###############################################################################

AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-798701233691}"
ECR_REPO_PATH="${ECR_REPO_PATH:-nitroberry}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
K8S_VERSION="${K8S_VERSION:-v1.29}"
GITHUB_USERNAME="${GITHUB_USERNAME:-abhimanyu8829}"
GITHUB_TOKEN="${GITHUB_TOKEN:-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}"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/dushyantajangid/NitroBerry-Platform.git}"
GIT_BRANCH="argocdTest"

ROOT_APP_PATH="../argocd/root-app.yaml"

###############################################################################
# COLORS
###############################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

###############################################################################
# HELPERS
###############################################################################

log() {
  echo ""
  echo -e "${BLUE}=======================================================${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${BLUE}=======================================================${NC}"
}

warn() {
  echo -e "${YELLOW}[WARN] $1${NC}"
}

error_exit() {
  echo -e "${RED}[ERROR] $1${NC}"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Detect WSL2 environment
is_wsl() {
  grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null || \
  [ -n "${WSL_DISTRO_NAME:-}" ]
}

retry() {
  local retries=5
  local count=0
  local delay=15   # increased from 10 → 15 for WSL networking

  until "$@"; do
    exit_code=$?
    count=$((count + 1))

    if [ "$count" -ge "$retries" ]; then
      echo "Command failed after $retries attempts."
      return "$exit_code"
    fi

    echo "Retry $count/$retries (waiting ${delay}s)..."
    sleep "$delay"
  done
}

###############################################################################
# WAIT FOR NODE READY  (NEW — must pass before installing anything)
###############################################################################

wait_for_node_ready() {
  log "Waiting for node to become Ready (up to 10 min)"

  local deadline=$((SECONDS + 600))
  while [ $SECONDS -lt $deadline ]; do
    local status
    status=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
    if [ "$status" = "Ready" ]; then
      echo "Node is Ready."
      kubectl get nodes
      return 0
    fi
    echo "Node status: '${status:-unknown}' — waiting 15s..."
    sleep 15
  done

  error_exit "Node never became Ready. Check CNI / containerd logs:\n  journalctl -u containerd -n 50\n  kubectl get pods -n kube-system"
}

###############################################################################
# INSTALL BASE PACKAGES
###############################################################################

install_base_packages() {

  log "Installing base packages"

  sudo apt-get update -y

  sudo apt-get install -y \
    curl \
    unzip \
    git \
    jq \
    ca-certificates \
    apt-transport-https \
    gpg

}

###############################################################################
# INSTALL AWS CLI
###############################################################################

install_awscli() {

  if command_exists aws; then
    log "AWS CLI already installed"
    return
  fi

  log "Installing AWS CLI"

  cd /tmp

  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o "awscliv2.zip"

  unzip -o awscliv2.zip

  sudo ./aws/install

  aws --version

}

###############################################################################
# INSTALL HELM
###############################################################################

install_helm() {

  if command_exists helm; then
    log "Helm already installed"
    return
  fi

  log "Installing Helm"

  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

}

###############################################################################
# INSTALL KUBERNETES
###############################################################################

install_kubernetes_packages() {

  if command_exists kubeadm && command_exists kubectl; then
    log "Kubernetes packages already installed"
    return
  fi

  log "Installing Kubernetes packages"

  # Swap — safe to skip in WSL (no swap by default)
  if ! is_wsl; then
    sudo swapoff -a || true
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true
  else
    warn "WSL detected — skipping swapoff"
  fi

  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

  sudo modprobe overlay   || warn "modprobe overlay failed (may be built-in in WSL)"
  sudo modprobe br_netfilter || warn "modprobe br_netfilter failed (may be built-in in WSL)"

  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

  # sysctl --system may fail in WSL; apply individual keys instead
  if is_wsl; then
    warn "WSL detected — applying sysctl keys individually"
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1  || true
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1 || true
    sudo sysctl -w net.ipv4.ip_forward=1                 || true
  else
    sudo sysctl --system
  fi

  sudo apt-get install -y containerd

  sudo mkdir -p /etc/containerd

  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' \
    /etc/containerd/config.toml

  sudo systemctl restart containerd
  sudo systemctl enable containerd

  sudo mkdir -p /etc/apt/keyrings

  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list

  sudo apt-get update -y

  sudo apt-get install -y kubelet kubeadm kubectl

  sudo apt-mark hold kubelet kubeadm kubectl

}

###############################################################################
# CREATE CLUSTER
###############################################################################

ensure_cluster() {

  mkdir -p "$HOME/.kube"

  if [ -f /etc/kubernetes/admin.conf ]; then
    sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    export KUBECONFIG="$HOME/.kube/config"
  fi

  if kubectl get nodes >/dev/null 2>&1; then
    log "Cluster already exists — checking node health"
    kubectl get nodes
    # Still wait: node might be NotReady (the original bug)
    wait_for_node_ready
    return
  fi

  install_kubernetes_packages

  log "Initializing Kubernetes cluster"

  # Use Flannel CIDR (10.244.0.0/16) — more reliable on WSL2 than Calico
  sudo kubeadm init --pod-network-cidr=10.244.0.0/16

  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  export KUBECONFIG="$HOME/.kube/config"

  grep -qxF 'export KUBECONFIG=$HOME/.kube/config' "$HOME/.bashrc" \
    || echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc"

  log "Installing Flannel CNI (WSL2-compatible)"

  kubectl apply -f \
    https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

  wait_for_node_ready

}

###############################################################################
# INSTALL STORAGE
###############################################################################

install_local_storage() {

  log "Installing local-path provisioner"

  kubectl apply -f \
    https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

  retry kubectl wait \
    --for=condition=Available \
    deployment/local-path-provisioner \
    -n local-path-storage \
    --timeout=300s

  log "Setting local-path as default StorageClass"

  kubectl patch storageclass local-path \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

}

###############################################################################
# INSTALL ARGOCD
###############################################################################

install_argocd() {

  log "Installing ArgoCD"

  kubectl create namespace "${ARGOCD_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Use server-side apply to avoid "annotations too long" error on ArgoCD CRDs
  kubectl apply \
    --server-side \
    --force-conflicts \
    -n "${ARGOCD_NAMESPACE}" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  retry kubectl wait \
    --for=condition=available \
    deployment/argocd-server \
    -n "${ARGOCD_NAMESPACE}" \
    --timeout=600s

}

###############################################################################
# INSTALL METALLB
###############################################################################

install_metallb_native() {

  log "Installing MetalLB Native"

  kubectl apply -f \
    https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml

  retry kubectl wait \
    --for=condition=Ready \
    pod \
    --all \
    -n metallb-system \
    --timeout=600s

}

###############################################################################
# CREATE NAMESPACES
###############################################################################

create_namespaces() {

  log "Creating namespaces"

  namespaces=(
    auth-namespace
    cockpit-namespace
    messenger-namespace
    social-namespace
    task-namespace
    vault-namespace
    workflow-namespace
    database-namespace
    traefik-ingress
    metallb-system
    gatekeeper-system
  )

  for ns in "${namespaces[@]}"; do
    kubectl create namespace "$ns" \
      --dry-run=client -o yaml | kubectl apply -f -
  done

}

###############################################################################
# CREATE DATABASE SECRET
###############################################################################

create_database_secret() {

  log "Creating postgres secret"

  kubectl create secret generic postgres-credentials \
    -n database-namespace \
    --from-literal=postgres-user=postgres \
    --from-literal=postgres-password=postgres123 \
    --dry-run=client -o yaml | kubectl apply -f -

}

###############################################################################
# CREATE GITHUB SECRET
###############################################################################

create_github_secret() {

  log "Creating GitHub repository secret"

  kubectl delete secret github-repo -n argocd --ignore-not-found=true

  kubectl create secret generic github-repo \
    -n argocd \
    --from-literal=url="${GITHUB_REPO}" \
    --from-literal=username="${GITHUB_USERNAME}" \
    --from-literal=password="${GITHUB_TOKEN}"

  kubectl label secret github-repo \
    -n argocd \
    argocd.argoproj.io/secret-type=repository \
    --overwrite

}

###############################################################################
# CREATE ECR SECRET
###############################################################################

create_ecr_secret() {

  log "Creating ECR OCI Helm repository secret"

  ECR_PASSWORD=$(aws ecr get-login-password --region "${AWS_REGION}")

  kubectl delete secret ecr-helm-repo -n argocd --ignore-not-found=true

  kubectl create secret generic ecr-helm-repo \
    -n argocd \
    --from-literal=name=nitroberry-ecr \
    --from-literal=url="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PATH}" \
    --from-literal=type=helm \
    --from-literal=enableOCI=true \
    --from-literal=username=AWS \
    --from-literal=password="${ECR_PASSWORD}"

  kubectl label secret ecr-helm-repo \
    -n argocd \
    argocd.argoproj.io/secret-type=repository \
    --overwrite

}

###############################################################################
# RESTART REPO SERVER
###############################################################################

restart_argocd_repo_server() {

  log "Restarting ArgoCD repo-server"

  kubectl rollout restart deployment argocd-repo-server -n argocd

  retry kubectl rollout status deployment argocd-repo-server \
    -n argocd \
    --timeout=300s

}

###############################################################################
# DEPLOY ROOT APP
###############################################################################

deploy_root_app() {

  log "Deploying NitroBerry root application"

  if [ ! -f "$ROOT_APP_PATH" ]; then
    error_exit "root-app.yaml not found at: $ROOT_APP_PATH"
  fi

  kubectl delete application nitroberry-platform-apps \
    -n argocd \
    --ignore-not-found=true

  sleep 10

  kubectl apply -f "$ROOT_APP_PATH"

  sleep 30

}

###############################################################################
# WAIT FOR DATABASE
###############################################################################

wait_for_database() {

  log "Waiting for postgres"

  retry kubectl wait \
    --for=condition=Ready \
    pod/postgres-0 \
    -n database-namespace \
    --timeout=600s

}

###############################################################################
# WAIT FOR ALL PODS
###############################################################################

wait_for_apps() {

  log "Waiting for all application pods"

  sleep 60

  kubectl get pods -A

}

###############################################################################
# START PORT FORWARDS
###############################################################################

start_port_forwards() {

  log "Starting ArgoCD UI port-forward"

  nohup kubectl port-forward svc/argocd-server \
    -n argocd \
    8080:443 >/tmp/argocd.log 2>&1 &

  log "Starting Traefik UI port-forward"

  nohup kubectl port-forward svc/traefik-service \
    -n traefik-ingress \
    9000:80 >/tmp/traefik.log 2>&1 &

}

###############################################################################
# SHOW FINAL STATUS
###############################################################################

show_status() {

  log "FINAL STATUS"

  echo ""
  kubectl get applications -n argocd

  echo ""
  kubectl get pods -A

  echo ""
  kubectl get svc -A

  echo ""
  echo "ArgoCD URL:      https://localhost:8080"
  echo "Traefik URL:     http://localhost:9000"
  echo "ArgoCD Username: admin"
  echo ""
  echo "ArgoCD Password:"
  kubectl -n argocd \
    get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  echo ""

}

###############################################################################
# MAIN
###############################################################################

main() {

  if is_wsl; then
    warn "WSL2 environment detected — applying WSL-compatible settings"
  fi

  log "[1/11] Installing packages"
  install_base_packages

  log "[2/11] Installing Helm"
  install_helm

  log "[3/11] Setting up Kubernetes"
  ensure_cluster          # now includes wait_for_node_ready internally

  log "[4/11] Installing Storage"
  install_local_storage

  log "[5/11] Installing ArgoCD"
  install_argocd

  log "[6/11] Installing MetalLB"
  install_metallb_native

  log "[7/11] Creating namespaces"
  create_namespaces

  log "[8/11] Creating secrets"
  create_database_secret
  create_github_secret
  create_ecr_secret

  log "[9/11] Restarting repo server"
  restart_argocd_repo_server

  log "[10/11] Deploying apps"
  deploy_root_app

  wait_for_database

  wait_for_apps

  log "[11/11] Starting dashboards"
  start_port_forwards

  show_status

  echo ""
  echo "======================================================="
  echo "NitroBerry Platform deployed successfully"
  echo "======================================================="

}

main