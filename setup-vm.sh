#!/bin/bash
set -euo pipefail

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/dushyantajangid/NitroBerry-Platform.git}"
GIT_BRANCH="${GIT_BRANCH:-argocdTest}"
AWS_REGION_DEFAULT="${AWS_REGION_DEFAULT:-ap-south-1}"
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

  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
  kubectl wait --for=condition=Ready nodes --all --timeout=600s
}

clone_or_update_repo() {
  log "Cloning or updating NitroBerry platform repository"
  REPO_DIR="$(basename "$GIT_REPO_URL" .git)"

  if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR"
    git fetch origin "$GIT_BRANCH"
    git checkout "$GIT_BRANCH"
    git pull --ff-only origin "$GIT_BRANCH"
  else
    git clone --branch "$GIT_BRANCH" "$GIT_REPO_URL"
    cd "$REPO_DIR"
  fi
}

install_argocd() {
  log "Installing ArgoCD if missing"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    echo "ArgoCD already installed."
  else
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null
  fi

  kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=600s
}

install_external_controllers() {
  log "Installing external controllers through Helm"
  helm repo add metallb https://metallb.github.io/metallb --force-update >/dev/null
  helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update >/dev/null
  helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
  helm repo update >/dev/null

  helm upgrade --install metallb metallb/metallb \
    --namespace metallb-system \
    --create-namespace \
    --wait

  helm upgrade --install gatekeeper gatekeeper/gatekeeper \
    --namespace gatekeeper-system \
    --create-namespace \
    --wait

  if helm show chart traefik/traefik-crds >/dev/null 2>&1; then
    helm upgrade --install traefik-crds traefik/traefik-crds \
      --namespace traefik-ingress \
      --create-namespace \
      --wait
  else
    echo "Traefik CRD chart was not found in the Helm repo. Install Traefik CRDs before syncing IngressRoute/Middleware resources."
  fi
}

configure_aws() {
  log "Configuring AWS credentials"
  aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
  aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
  aws configure set region "$AWS_REGION"
}

configure_kubernetes_secrets() {
  log "Creating runtime secrets outside Git"
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  AWS_TOKEN="$(aws ecr get-login-password --region "$AWS_REGION")"
  ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  ECR_HELM_REPO="${ECR_REGISTRY}/nitroberry"

  kubectl create namespace database-namespace --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace traefik-ingress --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace gatekeeper-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic nitroberry-ecr-helm-repo \
    --namespace argocd \
    --from-literal=type=helm \
    --from-literal=url="$ECR_HELM_REPO" \
    --from-literal=enableOCI=true \
    --from-literal=username=AWS \
    --from-literal=password="$AWS_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl label secret nitroberry-ecr-helm-repo \
    --namespace argocd \
    argocd.argoproj.io/secret-type=repository \
    --overwrite >/dev/null

  kubectl create secret generic postgres-credentials \
    --namespace database-namespace \
    --from-literal=postgres-user=postgres \
    --from-literal=postgres-password="$POSTGRES_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic aws-s3-backup-credentials \
    --namespace database-namespace \
    --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    --from-literal=AWS_DEFAULT_REGION="$AWS_REGION" \
    --from-literal=S3_BUCKET="$S3_BUCKET" \
    --dry-run=client -o yaml | kubectl apply -f -
}

push_infra_charts() {
  log "Packaging and pushing infrastructure Helm charts to ECR"
  ./Helm/push-infra-charts.sh "$AWS_REGION"
}

apply_argocd_apps() {
  log "Creating ArgoCD Applications for infrastructure Helm charts"
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  TMP_APPS="$(mktemp)"

  sed "s/798701233691.dkr.ecr.ap-south-1.amazonaws.com/${ECR_REGISTRY}/g" argocd-apps.yaml > "$TMP_APPS"
  kubectl apply -f "$TMP_APPS"
  rm -f "$TMP_APPS"
}

echo "=========================================================="
echo "    NitroBerry Production VM Setup & GitOps Bootstrap"
echo "=========================================================="
echo ""

read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo ""
read -p "AWS Region [${AWS_REGION_DEFAULT}]: " AWS_REGION
AWS_REGION="${AWS_REGION:-$AWS_REGION_DEFAULT}"
read -s -p "Postgres password for postgres-credentials: " POSTGRES_PASSWORD
echo ""
read -p "S3 backup bucket [nitroberry-db-backups]: " S3_BUCKET
S3_BUCKET="${S3_BUCKET:-nitroberry-db-backups}"

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Postgres password cannot be empty."
  exit 1
fi

install_base_packages
install_aws_cli
install_helm
configure_aws
ensure_kubernetes_cluster
clone_or_update_repo
install_argocd
install_external_controllers
configure_kubernetes_secrets
push_infra_charts
apply_argocd_apps

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
