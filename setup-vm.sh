#!/bin/bash
set -e

echo "=========================================================="
echo "    NitroBerry Production VM Setup & GitOps Bootstrap     "
echo "=========================================================="

# Prompt for AWS variables
echo "Please enter your AWS credentials (must have ECR access)."
read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo ""
read -p "AWS Region (e.g. ap-south-1): " AWS_REGION

# Git Repository Variables
GIT_REPO_URL="https://github.com/dushyantajangid/NitroBerry-Platform.git"
GIT_BRANCH="argocdTest" # Change to 'main' or other branch as needed

# 1. Install Dependencies & AWS CLI
echo ""
echo "=> [1/7] Installing required dependencies and AWS CLI v2..."
sudo apt-get update -y > /dev/null
sudo apt-get install -y curl unzip git jq > /dev/null
if ! command -v aws &> /dev/null; then
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install > /dev/null
    rm -rf aws awscliv2.zip
fi

# Configure AWS CLI
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set region "$AWS_REGION"

# 2. Install Standard Kubernetes (kubeadm, kubelet, containerd)
echo "=> [2/7] Installing standard Kubernetes (K8s) via kubeadm..."
if ! command -v kubectl &> /dev/null; then
    # Disable swap (required for kubeadm)
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    # Load modules and configure sysctl for containerd
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter

    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system > /dev/null

    # Install and configure containerd
    sudo apt-get update -y > /dev/null
    sudo apt-get install -y containerd > /dev/null
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd

    # Install kubeadm, kubelet, kubectl
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg > /dev/null
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    sudo apt-get update -y > /dev/null
    sudo apt-get install -y kubelet kubeadm kubectl > /dev/null
    sudo apt-mark hold kubelet kubeadm kubectl > /dev/null

    # Initialize Kubernetes cluster
    echo "=> Initializing Kubernetes cluster with kubeadm..."
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16

    # Set up kubeconfig for current user
    mkdir -p ~/.kube
    sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    export KUBECONFIG=~/.kube/config
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

    # Install Calico CNI for networking
    echo "=> Installing Calico CNI..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

    # Untaint the control-plane node so workloads can run on this single-node cluster
    echo "=> Untainting master node to allow pod scheduling..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
else
    echo "Kubernetes is already installed."
fi

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
kubectl apply -f Helm/charts/nitroberry/templates/ecr-helper.yaml

# 6. Apply Core Infrastructure & Secrets
echo "=> [6/7] Applying Core Infrastructure (MetalLB, Traefik, Postgres)..."
kubectl apply -f "Legacy yaml/00-namespaces.yaml"

# Install MetalLB explicitly (CRDs first, wait, then IP pool)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/manifests/metallb.yaml
kubectl wait --for=condition=Ready pods --all -n metallb-system --timeout=300s
kubectl apply -f "Legacy yaml/01-metallb.yaml"

# Core services
kubectl apply -f "Legacy yaml/02-postgres.yaml"
kubectl apply -f "Legacy yaml/03-traefik-rbac.yaml"
kubectl apply -f "Legacy yaml/04-traefik-install.yaml"
kubectl apply -f "Legacy yaml/05-traefik-middlewares.yaml"

echo "=> Applying Initial Secrets (ensure 'Legacy yaml/12-secrets.yaml' has real passwords before production!)"
kubectl apply -f "Legacy yaml/12-secrets.yaml"

# 7. Start GitOps deployment via ArgoCD
echo "=> [7/7] Applying ArgoCD Apps (Triggering GitOps deployment)..."

# Dynamically update the ECR URL in argocd-apps.yaml to match the current AWS Account and Region
sed -i "s/798701233691.dkr.ecr.ap-south-1.amazonaws.com/${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/g" argocd-apps.yaml

kubectl apply -f argocd-apps.yaml

echo ""
echo "=========================================================="
echo "✨ DEPLOYMENT BOOTSTRAP COMPLETE ✨"
echo "=========================================================="
echo "ArgoCD will now pull all 11 Helm charts from AWS ECR and deploy the microservices."
echo ""
echo "To check ArgoCD UI, port-forward to your local machine:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "Your ArgoCD default 'admin' password is:"
echo "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo "=========================================================="
