# NitroBerry Platform Infrastructure

> **GitOps-driven Kubernetes platform for the NitroBerry microservices ecosystem.**
> This repository contains the complete infrastructure code to bootstrap a bare-metal/VM Kubernetes cluster, configure ArgoCD, and deploy the entire NitroBerry microservices suite (13 APIs and Workers) via AWS ECR OCI Helm charts.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Microservices Map](#microservices-map)
- [Full Step-by-Step Production Deployment Guide](#full-step-by-step-production-deployment-guide)
  - [Phase 1: Local Machine Preparation (AWS & ECR)](#phase-1-local-machine-preparation-aws--ecr)
  - [Phase 2: Connecting to the Production VM](#phase-2-connecting-to-the-production-vm)
  - [Phase 3: VM Bootstrap & Configuration](#phase-3-vm-bootstrap--configuration)
  - [Phase 4: Running the Setup Script](#phase-4-running-the-setup-script)
  - [Phase 5: Verification](#phase-5-verification)
  - [Phase 6: Accessing ArgoCD](#phase-6-accessing-argocd)
- [Day-2 Operations](#day-2-operations)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository owns the **entire Kubernetes platform layer**. It handles:

1. **Cluster Bootstrap**: Single-node `kubeadm` cluster on an Ubuntu VM with Calico CNI.
2. **GitOps Engine**: ArgoCD following the "App-of-Apps" pattern.
3. **Networking**: MetalLB (for LoadBalancer IPs) and Traefik (Ingress + TLS).
4. **Data Layer**: PostgreSQL, PgBouncer (connection pooling), and Redis.
5. **Security**: OPA Gatekeeper policies.
6. **ECR Automation**: CronJob to automatically refresh AWS ECR tokens.
7. **Microservices Orchestration**: Automated deployment of 7 microservice domains.

---

## Architecture

The deployment follows the **App-of-Apps** pattern orchestrated by ArgoCD.

```text
argocd-apps.yaml (Root Application)
  └── helm/argocd-apps/ (Helm chart that generates child Applications)
        ├── metallb          (sync-wave 1)  ← Infrastructure deploys first
        ├── postgres         (sync-wave 2)
        ├── pgbouncer        (sync-wave 3)
        ├── redis            (sync-wave 3)
        ├── traefik          (sync-wave 4)
        ├── opa-gatekeeper   (sync-wave 5)
        ├── auth-api         (sync-wave 10) ← APIs deploy next
        ├── vault-api        (sync-wave 11)
        ├── cockpit-api      (sync-wave 12)
        ├── social-api       (sync-wave 13)
        ├── task-api         (sync-wave 14)
        ├── messenger-api    (sync-wave 10)
        ├── workflow-api     (sync-wave 16)
        ├── auth-worker      (sync-wave 20) ← Workers deploy last
        ├── vault-worker     (sync-wave 21)
        ├── cockpit-worker   (sync-wave 22)
        ├── social-worker    (sync-wave 23)
        ├── task-worker      (sync-wave 24)
        └── workflow-worker  (sync-wave 26)
```

---

## Microservices Map

| Service | ECR Helm Chart | Namespace | Health Probe | Notes |
|---------|---------------|-----------|-------------|-------|
| Auth API | `nitroberry/auth-api-helm` | `auth-namespace` | `/api/health` | Identity & authentication |
| Auth Worker | `nitroberry/auth-worker-helm` | `auth-namespace` | — | Background jobs |
| Vault API | `nitroberry/vault-api-helm` | `vault-namespace` | `/api/health` | Secure data storage |
| Vault Worker | `nitroberry/vault-worker-helm` | `vault-namespace` | — | Background jobs |
| Cockpit API | `nitroberry/cockpit-api-helm` | `cockpit-namespace` | `/api/health` | Admin control plane |
| Cockpit Worker | `nitroberry/cockpit-worker-helm` | `cockpit-namespace` | — | Background jobs |
| Social API | `nitroberry/social-api-helm` | `social-namespace` | `/api/health` | Social features |
| Social Worker | `nitroberry/social-worker-helm` | `social-namespace` | — | Background jobs |
| Task API | `nitroberry/task-api-helm` | `task-namespace` | `/api/health` | Task management |
| Task Worker | `nitroberry/task-worker-helm` | `task-namespace` | — | Background jobs |
| Messenger API | `nitroberry/messenger-api-helm` | `messenger-namespace` | `/socket.io/socket.io.js` | WebSocket-only (Socket.io) |
| Workflow API | `nitroberry/workflow-api-helm` | `workflow-namespace` | `/api/health` | Orchestration |
| Workflow Worker | `nitroberry/workflow-worker-helm` | `workflow-namespace` | — | Background jobs |

---

## Full Step-by-Step Production Deployment Guide

**Follow these exact steps, copy-pasting the commands one by one, to take a fresh Ubuntu VM to a fully running production Kubernetes cluster.**

### Phase 1: Local Machine Preparation (AWS & ECR)

Before touching the VM, you must prepare your AWS ECR registries and push the infrastructure charts from your **local machine**.

**1. Configure AWS CLI locally**
Ensure you have the AWS CLI installed on your local machine and configured with an IAM user that has ECR administrative privileges.
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, region (e.g., ap-south-1), and format (json)
```

**2. Verify AWS Access**
```bash
aws sts get-caller-identity
# Ensure it prints your Account ID and ARN successfully.
```

**3. Clone this repository locally**
```bash
git clone https://github.com/dushyantajangid/NitroBerry-Platform.git
cd NitroBerry-Platform
git checkout argocdTest
```

**4. Lint the infrastructure charts**
```bash
helm lint helm/helm/metallb helm/helm/postgres helm/helm/pgbouncer helm/helm/redis helm/helm/traefik helm/helm/opa-gatekeeper helm/argocd-apps
# Output should end with: 7 chart(s) linted, 0 chart(s) failed
```

**5. Push the infrastructure charts to AWS ECR**
This script automatically logs into ECR, creates the repositories if they don't exist, packages the Helm charts, and pushes them.
```bash
chmod +x helm/push-infra-charts.sh
./helm/push-infra-charts.sh ap-south-1
```

*(Note: The 13 product microservice charts must also exist in ECR. These are typically pushed via GitHub Actions from their respective application repositories.)*

---

### Phase 2: Connecting to the Production VM

**Prerequisites for the VM:**
* OS: Ubuntu 20.04 or 22.04 LTS
* RAM: Minimum 8 GB (16 GB recommended)
* CPU: Minimum 2 cores (4 recommended)

**1. SSH into your Ubuntu VM**
Replace `<VM_PUBLIC_IP>` with your server's actual IP address.
```bash
ssh ubuntu@<VM_PUBLIC_IP>
```

---

### Phase 3: VM Bootstrap & Configuration

Execute the following commands **directly on the Ubuntu VM**.

**1. Update system packages**
```bash
sudo apt-get update -y && sudo apt-get upgrade -y
```

**2. Install AWS CLI v2 on the VM**
```bash
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt-get install unzip -y
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

**3. Configure AWS Credentials on the VM**
The cluster needs to pull images from ECR. Configure AWS for the `ubuntu` user:
```bash
aws configure
# Enter the EXACT SAME Access Key, Secret Key, and Region (ap-south-1) as you did locally.
```
Verify:
```bash
aws sts get-caller-identity
```

**4. Copy AWS Credentials for the Root User**
Our automated ECR token refresher runs as a Kubernetes CronJob that mounts the `/root/.aws` directory from the host. Therefore, `root` must also have these credentials.
```bash
sudo mkdir -p /root/.aws
sudo cp -r ~/.aws/* /root/.aws/
sudo chmod -R 600 /root/.aws/*
sudo chown -R root:root /root/.aws/
```
Verify root access:
```bash
sudo aws sts get-caller-identity
```

**5. Clone the Repository on the VM**
```bash
git clone https://github.com/dushyantajangid/NitroBerry-Platform.git
cd NitroBerry-Platform
git checkout argocdTest
```

---

### Phase 4: Running the Setup Script

You are now ready to run the master bootstrap script. This script will install Kubernetes, initialize the cluster, install Calico, install ArgoCD, and trigger the entire GitOps deployment.

**1. Export required environment variables**
```bash
export AWS_REGION="ap-south-1"
export GIT_REPO_URL="https://github.com/dushyantajangid/NitroBerry-Platform.git"
export GIT_BRANCH="argocdTest"
```

**2. Execute the bootstrap script**
```bash
chmod +x setup-vm.sh
./setup-vm.sh
```

**Grab a coffee ☕. This script takes 5-10 minutes.** 
When it completes, it will print out your **ArgoCD Admin Password**. 
⚠️ **COPY AND SAVE THIS PASSWORD IMMEDIATELY!** ⚠️

---

### Phase 5: Verification

Verify that the cluster is healthy and ArgoCD is deploying your applications.

**1. Check Kubernetes Node Status**
```bash
kubectl get nodes
# Status should be "Ready"
```

**2. Check the Status of all Pods**
```bash
kubectl get pods -A
```
*Wait until all pods across all namespaces (auth-namespace, database-namespace, etc.) show `1/1` in the `READY` column and `Running` in the `STATUS` column. This may take a few minutes as ArgoCD orchestrates the rollout.*

**3. Check ArgoCD Application Sync Status**
```bash
kubectl get applications -n argocd
```
*Every single application should have a `SYNC STATUS` of `Synced` and a `HEALTH STATUS` of `Healthy`.*

**4. Verify Database Connectivity**
```bash
# Test direct PostgreSQL connection
kubectl exec -n database-namespace postgres-0 -- pg_isready -h postgres-service -p 5432 -U postgres
# Expected: "postgres-service:5432 - accepting connections"

# Test PgBouncer connection
kubectl exec -n database-namespace postgres-0 -- pg_isready -h pgbouncer-service -p 6432 -U postgres
# Expected: "pgbouncer-service:6432 - accepting connections"

# Test Redis connection
kubectl exec -n database-namespace deploy/redis -- redis-cli ping
# Expected: "PONG"
```

---

### Phase 6: Accessing ArgoCD

You can securely access the ArgoCD Web UI from your local machine by port-forwarding.

**1. On the Ubuntu VM, start the port-forward:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
```

**2. On your local computer, open your web browser:**
Navigate to: `https://<VM_PUBLIC_IP>:8080`
*(Accept the self-signed certificate warning)*

**3. Login:**
* **Username:** `admin`
* **Password:** *(The password you saved at the end of Phase 4)*

*(If you lost the password, retrieve it on the VM using this command:)*
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
```

---

## Day-2 Operations

### Updating a Microservice Version

When developers release a new version of a microservice (e.g., `auth-api` v0.0.7):
1. On your local machine, edit `helm/argocd-apps/chart-tags.yaml`.
2. Change the version: `auth-api: "0.0.7"`
3. Commit and push the change to GitHub:
   ```bash
   git add helm/argocd-apps/chart-tags.yaml
   git commit -m "chore: bump auth-api to v0.0.7"
   git push origin argocdTest
   ```
4. ArgoCD will automatically detect the Git change within 3 minutes, pull the new v0.0.7 Helm chart from ECR, and perform a rolling update on the cluster.

### Forcing ArgoCD to Refresh Immediately
If you don't want to wait 3 minutes for ArgoCD to poll GitHub:
```bash
kubectl annotate application -n argocd nitroberry-platform-apps argocd.argoproj.io/refresh=hard --overwrite
```

### Manually Refreshing ECR Credentials
The CronJob handles this automatically every 6 hours, but you can force it manually if you get an ImagePullBackOff due to unauthorized ECR access:
```bash
kubectl create job --from=cronjob/ecr-token-refresher ecr-token-refresher-manual -n argocd
# View the logs to ensure success
kubectl logs -n argocd job/ecr-token-refresher-manual
```

---

## Troubleshooting

### 1. Pods are stuck in `ImagePullBackOff` or `ErrImagePull`
This means Kubernetes cannot authenticate with AWS ECR.
* Run the manual ECR token refresh command (see Day-2 Operations).
* Verify `/root/.aws/credentials` exists and is correct on the VM.

### 2. ArgoCD Application shows `Unknown` Sync Status
This usually means ArgoCD cannot read the Helm chart from ECR or cannot read the Git repository.
```bash
# Check the specific error message
kubectl describe application <app-name> -n argocd

# Check the Repo Server logs
kubectl logs -n argocd deploy/argocd-repo-server --tail=100
```
* **Private Git Repo?** If your GitHub repo is private, you must add a Personal Access Token (PAT) to ArgoCD as a Repository Credential.
* **Missing Chart?** Ensure the chart version listed in `chart-tags.yaml` actually exists in ECR.

### 3. API Pod is stuck in `CrashLoopBackOff`
This happens if the application is crashing on startup, or if the Kubernetes Health Probes are failing.
```bash
# Check the pod logs
kubectl logs -n <namespace> <pod-name>

# Check the probe events
kubectl describe pod -n <namespace> <pod-name>
```
*Note: `messenger-api` is a WebSocket server and does not have an `/api/health` REST endpoint. Its health probe is deliberately configured to hit `/socket.io/socket.io.js` in `helm/argocd-apps/values.yaml`.*

### 4. MetalLB External IP is `<pending>`
If Traefik isn't getting an IP address:
```bash
kubectl get svc -n traefik-ingress traefik-service
```
This means the IP pool defined in `helm/helm/metallb/values.yaml` is exhausted or misconfigured. Ensure the IP range in that file is valid for your VM's local network subnets.
