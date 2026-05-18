#!/bin/bash
set -euo pipefail

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/dushyantajangid/NitroBerry-Platform.git}"
GIT_BRANCH="${GIT_BRANCH:-argocdTest}"
AWS_REGION_DEFAULT="${AWS_REGION_DEFAULT:-ap-south-1}"
AWS_REGION="${AWS_REGION:-$AWS_REGION_DEFAULT}"
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
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y curl unzip git jq ca-certificates apt-transport-https gpg >/dev/null
}

install_aws_cli() {
  if command_exists aws; then
    echo "AWS CLI already installed."
    return
  fi

  log "Installing AWS CLI v2"
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  sudo ./aws/install >/dev/null
  rm -rf aws awscliv2.zip
}

install_helm() {
  if command_exists helm; then
    echo "Helm already installed."
    return
  fi

  log "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_gatekeeper() {
  if kubectl get deployment gatekeeper-controller-manager -n gatekeeper-system >/dev/null 2>&1; then
    echo "Gatekeeper already installed."
    return
  fi

  log "Installing OPA Gatekeeper controller"
  kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.14.0/deploy/gatekeeper.yaml
  kubectl wait --for=condition=available deployment/gatekeeper-controller-manager -n gatekeeper-system --timeout=300s
}

install_kubernetes_packages() {
  if command_exists kubeadm && command_exists kubelet && command_exists kubectl; then
    echo "Kubernetes packages already installed."
    return
  fi

  log "Installing kubeadm, kubelet, kubectl, and containerd"
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

  sudo apt-get install -y containerd >/dev/null
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd >/dev/null

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

# Run bootstrap sequence
install_base_packages
install_aws_cli
install_helm
ensure_kubernetes_cluster

echo "=> Waiting for Kubernetes node to be ready..."
sleep 10
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# 3. Clone Repository
echo "=> [3/7] Cloning NitroBerry Git repository..."
if [ -d "NitroBerry-Platform" ]; then
    rm -rf NitroBerry-Platform
fi
git clone "$GIT_REPO_URL"
# Extract directory name from repo URL
REPO_DIR=$(basename "$GIT_REPO_URL" .git)
cd "$REPO_DIR"
git checkout "$GIT_BRANCH" || true

# 4. Install ArgoCD
echo "=> [4/7] Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml > /dev/null

echo "=> Waiting for ArgoCD server to be ready (this may take a minute)..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# 5. ECR Login & ArgoCD Repo Configuration
echo "=> [5/7] Configuring AWS ECR tokens and CronJob..."
AWS_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

kubectl create secret generic ecr-regcred \
  --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$AWS_TOKEN \
  -n argocd --dry-run=client -o yaml | kubectl apply -f -

# Deploy the ecr-helper to keep tokens fresh forever
kubectl apply -f helm/ecr-helper.yaml

# 6. Apply Core Infrastructure & Secrets
echo "=> [6/7] Applying Core Infrastructure (MetalLB and pre-provisioning secrets)..."

# Pre-create namespaces
kubectl create namespace database-namespace --dry-run=client -o yaml | kubectl apply -f -

# Create Postgres credentials secret
kubectl create secret generic postgres-credentials \
  --from-literal=postgres-user=postgres \
  --from-literal=postgres-password=nitroberry-prod-db-pass \
  -n database-namespace --dry-run=client -o yaml | kubectl apply -f -

# Install MetalLB operator explicitly (CRDs first, wait, then IP pool config is managed by helm)
echo "=> Installing MetalLB operator..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
echo "=> Waiting for MetalLB operator to be ready..."
kubectl wait --for=condition=Ready pods --all -n metallb-system --timeout=300s

install_gatekeeper

# 7. Start GitOps deployment via ArgoCD
echo "=> [7/7] Applying ArgoCD Apps (Triggering GitOps deployment)..."

# Dynamically update the ECR URL in argocd-apps.yaml to match the current AWS Account and Region
sed -i "s/798701233691.dkr.ecr.ap-south-1.amazonaws.com/${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/g" argocd-apps.yaml

kubectl apply -f argocd-apps.yaml

echo ""
echo "=========================================================="
echo "NitroBerry GitOps bootstrap complete."
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
