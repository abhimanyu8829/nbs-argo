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

# 2. Install K3s (Lightweight bare-metal Kubernetes)
echo "=> [2/7] Installing K3s (Kubernetes)..."
if ! command -v kubectl &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    export KUBECONFIG=~/.kube/config
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
else
    echo "Kubernetes is already installed."
fi

echo "=> Waiting for Kubernetes node to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# 3. Clone Repository
echo "=> [3/7] Cloning NitroBerry Git repository..."
if [ -d "NitroBerry-Platform" ]; then
    rm -rf NitroBerry-Platform
fi
git clone https://github.com/dushyantajangid/NitroBerry-Platform.git
cd NitroBerry-Platform
git checkout argocdTest || true

# 4. Install ArgoCD
echo "=> [4/7] Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml > /dev/null

echo "=> Waiting for ArgoCD server to be ready (this may take a minute)..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# 5. ECR Login & ArgoCD Repo Configuration
echo "=> [5/7] Configuring AWS ECR tokens and CronJob..."
AWS_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)
kubectl create secret generic ecr-regcred \
  --docker-server=798701233691.dkr.ecr.$AWS_REGION.amazonaws.com \
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
