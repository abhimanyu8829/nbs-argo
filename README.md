# NitroBerry Platform Infrastructure: The Ultimate Production Deployment Guide

> **GitOps-driven Kubernetes platform for the NitroBerry microservices ecosystem.**
> This repository contains the complete infrastructure code to bootstrap a bare-metal/VM Kubernetes cluster, configure ArgoCD, and deploy the entire NitroBerry microservices suite (13 APIs and Workers) via AWS ECR OCI Helm charts.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Microservices Map](#microservices-map)
- [The Ultimate Step-by-Step Production Deployment Guide](#the-ultimate-step-by-step-production-deployment-guide)
  - [Phase 1: Local Machine Preparation (AWS & ECR)](#phase-1-local-machine-preparation-aws--ecr)
  - [Phase 2: Procuring and Connecting to the VM](#phase-2-procuring-and-connecting-to-the-vm)
  - [Phase 3: VM Initialization & AWS Configuration](#phase-3-vm-initialization--aws-configuration)
  - [Phase 4: Cloning the Repository & Running the Setup Script](#phase-4-cloning-the-repository--running-the-setup-script)
  - [Phase 5: Exhaustive Verification](#phase-5-exhaustive-verification)
  - [Phase 6: Accessing the ArgoCD Dashboard](#phase-6-accessing-the-argocd-dashboard)
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
argocd/root-app.yaml (Root Application)
  └── argocd/apps/ (Helm chart that generates child Applications)
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

## The Ultimate Step-by-Step Production Deployment Guide

**Follow this guide meticulously. Do not skip any steps. This guide takes you from an empty local machine all the way to a fully functioning Kubernetes production cluster.**

### Phase 1: Local Machine Preparation (AWS & ECR)

Before touching any production servers, you must prepare your AWS environment and push the foundational infrastructure charts to Elastic Container Registry (ECR). Perform these steps on your **personal computer / local machine**.

#### Step 1.1: Install Prerequisites Locally
Ensure you have the following installed on your local computer:
1. **Git:** `git --version`
2. **AWS CLI v2:** `aws --version`
3. **Helm 3:** `helm version`

#### Step 1.2: Configure AWS Credentials
You need an AWS IAM User with programmatic access (Access Key ID and Secret Access Key). This user must have `AmazonEC2ContainerRegistryFullAccess`.
```bash
aws configure
```
* **AWS Access Key ID:** `AKIA...` (Enter your key)
* **AWS Secret Access Key:** `wJalrXUtn...` (Enter your secret)
* **Default region name:** `ap-south-1` (Or your preferred region)
* **Default output format:** `json`

Verify it works:
```bash
aws sts get-caller-identity
```
*(You should see your Account ID and ARN outputted.)*

#### Step 1.3: Clone the Platform Repository
Download this GitOps repository to your local machine:
```bash
git clone https://github.com/dushyantajangid/NitroBerry-Platform.git
cd NitroBerry-Platform
git checkout argocdTest
```

#### Step 1.4: Lint the Infrastructure Charts
Validate that the Helm charts are syntactically correct before pushing:
```bash
helm lint helm/metallb helm/postgres helm/pgbouncer helm/redis helm/traefik helm/opa-gatekeeper argocd/apps
```
*(Expected Output: `7 chart(s) linted, 0 chart(s) failed`)*

#### Step 1.5: Push Infrastructure Charts to ECR
Run the automated script to package and push the 6 infrastructure charts to your AWS account.
```bash
chmod +x script/push-infra-charts.sh
./script/push-infra-charts.sh ap-south-1
```
*(This script logs into ECR, creates the repos if they don't exist, and uploads the `.tgz` packages).*

**Note:** The 13 product microservice charts (`auth-api-helm`, `social-api-helm`, etc.) must also exist in ECR. These are typically pushed via GitHub Actions from their respective application repositories. Ensure all 19 repositories exist in ECR before proceeding.

---

### Phase 2: Procuring and Connecting to the VM

#### Step 2.1: Provision the Virtual Machine
Go to your cloud provider (AWS EC2, DigitalOcean, Azure, etc.) and launch a Virtual Machine with the following specifications:
* **Operating System:** Ubuntu 20.04 LTS or 22.04 LTS
* **CPU:** 4 vCPUs (Minimum 2)
* **RAM:** 16 GB (Minimum 8 GB)
* **Disk Space:** 50 GB SSD
* **Network:** Must have a Public IP address assigned.

**AWS EC2 Security Group (Firewall) Configuration:**
You must configure the Security Group attached to your EC2 instance to whitelist the following inbound rules:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| SSH | TCP | `22` | `0.0.0.0/0` (Or your IP) | Required to connect to the server |
| HTTP | TCP | `80` | `0.0.0.0/0` | Required for Let's Encrypt ACME challenges & web traffic |
| HTTPS | TCP | `443` | `0.0.0.0/0` | Required for secure web traffic to the Traefik Ingress |
| Custom TCP | TCP | `8080` | `0.0.0.0/0` | Optional: To access ArgoCD UI without port-forwarding |

*Note: All outbound (egress) traffic should be allowed (`0.0.0.0/0` on All Traffic) so the server can download packages and pull from ECR.*

#### Step 2.2: SSH Into the Virtual Machine
Locate the private SSH key (`.pem` or `.id_rsa`) you assigned to the VM.
Open your local terminal and connect:
```bash
# If using a .pem file:
chmod 400 your-key.pem
ssh -i your-key.pem ubuntu@<VM_PUBLIC_IP>

# If using standard SSH keys:
ssh ubuntu@<VM_PUBLIC_IP>
```
*(Type `yes` if prompted to accept the host key footprint).*

You should now see the `ubuntu@...:~$` prompt. You are inside the production server.

---

### Phase 3: VM Initialization & AWS Configuration

Execute all of the following commands **directly on the Ubuntu VM**.

#### Step 3.1: Update the Operating System
Ensure the server has the latest security patches and package lists.
```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```

#### Step 3.2: Install Utility Packages
```bash
sudo apt-get install -y curl unzip git jq apt-transport-https ca-certificates
```

#### Step 3.3: Install the AWS CLI on the VM
Kubernetes and ArgoCD will need the AWS CLI to authenticate with ECR.
```bash
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```
Verify installation:
```bash
aws --version
```

#### Step 3.4: Configure AWS Credentials for the `ubuntu` User
You must configure the exact same AWS credentials you used on your local machine.
```bash
aws configure
```
* **AWS Access Key ID:** `AKIA...` (Enter your key)
* **AWS Secret Access Key:** `wJalrXUtn...` (Enter your secret)
* **Default region name:** `ap-south-1`
* **Default output format:** `json`

Verify the configuration worked:
```bash
aws sts get-caller-identity
```

#### Step 3.5: Configure AWS Credentials for the `root` User
**CRITICAL STEP:** Our automated ECR token refresher runs as a Kubernetes CronJob. It mounts the `/root/.aws` directory from the host to generate new Docker registry tokens every 6 hours. If `root` does not have AWS credentials, your cluster will eventually fail to pull images!

Copy the credentials you just configured to the root user's home directory:
```bash
sudo mkdir -p /root/.aws
sudo cp -r ~/.aws/* /root/.aws/
sudo chmod -R 600 /root/.aws/*
sudo chown -R root:root /root/.aws/
```

Verify that the `root` user can successfully authenticate:
```bash
sudo aws sts get-caller-identity
```
*(If this fails, do not proceed until it is fixed).*

---

### Phase 4: Cloning the Repository & Running the Setup Script

#### Step 4.1: Clone the Platform Repository
Download the GitOps infrastructure code to the VM.
```bash
git clone https://github.com/dushyantajangid/NitroBerry-Platform.git
cd NitroBerry-Platform
git checkout argocdTest
```

#### Step 4.2: Export Configuration Variables
The setup script relies on these variables to know where to pull the GitOps configuration from.
```bash
export AWS_REGION="ap-south-1"
export GIT_REPO_URL="https://github.com/dushyantajangid/NitroBerry-Platform.git"
export GIT_BRANCH="argocdTest"
```

#### Step 4.3: Execute the Master Setup Script
This script does all the heavy lifting. It installs `kubeadm`, `kubelet`, `containerd`, creates the Kubernetes cluster, removes the master taint, installs ArgoCD, installs MetalLB, creates the ECR helper CronJob, and finally applies the root `argocd/root-app.yaml` file to trigger the GitOps deployment.

```bash
chmod +x script/installation/setup-vm.sh
./script/installation/setup-vm.sh
```

**Wait patiently.** This script takes approximately 5 to 10 minutes to execute. You will see logs scrolling by as it installs packages and pulls container images.

#### Step 4.4: Save the ArgoCD Admin Password
When the script completes, it will print a success banner. At the very bottom of this banner is your **ArgoCD Admin Password**.

```text
==========================================================
NitroBerry GitOps bootstrap complete.
ArgoCD is now configured to pull infrastructure Helm charts from ECR.
...
ArgoCD admin password:
zK9aXv... <--- THIS IS YOUR PASSWORD
==========================================================
```
⚠️ **COPY THIS PASSWORD TO A SECURE LOCATION IMMEDIATELY.** ⚠️

*(If you lose it, you can retrieve it later with: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo`)*

---

### Phase 5: Exhaustive Verification

ArgoCD is now running in the background, pulling all 19 Helm charts from AWS ECR and deploying them to Kubernetes. You must monitor this process to ensure everything stabilizes.

#### Step 5.1: Verify Kubernetes Node Health
```bash
kubectl get nodes
```
* **Expected Output:** You should see one node. Its `STATUS` must be `Ready` and `ROLES` must be `control-plane`.

#### Step 5.2: Watch the Pod Rollout
Run the following command to watch all pods across all namespaces in real-time.
```bash
kubectl get pods -A -w
```
*(Press `Ctrl+C` to exit the watch mode).*

**What you are looking for:**
Every single pod must eventually reach a `1/1` state in the `READY` column, and `Running` in the `STATUS` column.
* The infrastructure pods (Postgres, Redis, PgBouncer, Traefik, Gatekeeper) will start first.
* The API pods (`auth-api`, `social-api`, etc.) will start next.
* The Worker pods (`auth-worker`, `task-worker`, etc.) will start last.
* *Note: It is normal for some pods to restart 1 or 2 times during the initial boot phase as they wait for databases to become available.*

#### Step 5.3: Verify ArgoCD Application Sync Status
```bash
kubectl get applications -n argocd
```
* **Expected Output:** Every application (all 20 of them) must display `Synced` under `SYNC STATUS` and `Healthy` under `HEALTH STATUS`.

#### Step 5.4: Test Database Connectivity
Ensure the databases are accepting connections internally.

**Test PostgreSQL directly:**
```bash
kubectl exec -n database-namespace postgres-0 -- pg_isready -h postgres-service -p 5432 -U postgres
# Expected Output: postgres-service:5432 - accepting connections
```

**Test PgBouncer (Connection Pooler):**
```bash
kubectl exec -n database-namespace postgres-0 -- pg_isready -h pgbouncer-service -p 6432 -U postgres
# Expected Output: pgbouncer-service:6432 - accepting connections
```

**Test Redis:**
```bash
kubectl exec -n database-namespace deploy/redis -- redis-cli ping
# Expected Output: PONG
```

#### Step 5.5: Verify Gatekeeper Security Policies
Ensure the OPA Gatekeeper constraints have successfully applied.
```bash
kubectl get constrainttemplates
kubectl get constraints
```
* **Expected Output:** You should see 6 policies listed, including `blocklatesttag`, `blockprivilegedcontainers`, `blockrootcontainers`, `requirelabels`, `requirereadonlyrootfs`, and `requireresourcelimits`.

---

### Phase 6: Accessing the ArgoCD Dashboard

ArgoCD provides a beautiful UI to visualize your entire microservices architecture. Since this is a production cluster, the ArgoCD server is not exposed to the public internet by default. You will use port-forwarding to access it securely.

#### Step 6.1: Start the Port Forward on the VM
Run this command on the Ubuntu VM. It will block the terminal (this is expected).
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
```

#### Step 6.2: Open the Dashboard in your Local Browser
Open Google Chrome or Firefox on your personal computer and navigate to:
```text
https://<VM_PUBLIC_IP>:8080
```
*(Your browser will warn you about a self-signed certificate. Click "Advanced" and "Proceed to..." to bypass the warning).*

#### Step 6.3: Log In
* **Username:** `admin`
* **Password:** *(Paste the password you copied at the end of Phase 4).*

You will now see a grid of all your applications. They should all have a green heart (Healthy) and a green checkmark (Synced).

*(To stop the port-forward on the VM, simply press `Ctrl+C` in the terminal).*

---

## Day-2 Operations

### Updating a Microservice Version
When developers release a new version of a microservice (e.g., they push `auth-api` v0.0.7 to ECR), you deploy it via GitOps:

1. On your **local machine**, edit `argocd/apps/chart-tags.yaml`.
2. Change the version string: `auth-api: "0.0.7"`
3. Commit and push the change to GitHub:
   ```bash
   git add argocd/apps/chart-tags.yaml
   git commit -m "chore: bump auth-api to v0.0.7"
   git push origin argocdTest
   ```
4. ArgoCD will automatically detect the Git change within 3 minutes, pull the new v0.0.7 Helm chart from ECR, and perform a rolling update on the cluster with zero downtime.

### Forcing ArgoCD to Refresh Immediately
If you push a Git commit and don't want to wait 3 minutes for ArgoCD's polling cycle:
```bash
kubectl annotate application -n argocd nitroberry-platform-apps argocd.argoproj.io/refresh=hard --overwrite
```

### Manually Refreshing ECR Credentials
The `ecr-helper` CronJob handles this automatically every 6 hours. However, if you ever see `ImagePullBackOff` errors because of unauthorized ECR access, you can trigger a manual refresh immediately:
```bash
kubectl create job --from=cronjob/ecr-token-refresher ecr-token-refresher-manual -n argocd
# View the logs to ensure it worked
kubectl logs -n argocd job/ecr-token-refresher-manual
```

---

## Troubleshooting

### 1. Pods are stuck in `ImagePullBackOff` or `ErrImagePull`
This means Kubernetes cannot authenticate with AWS ECR to pull the Docker image.
* **Fix 1:** Run the manual ECR token refresh command (see Day-2 Operations).
* **Fix 2:** Verify `/root/.aws/credentials` exists and is correct on the VM (`sudo cat /root/.aws/credentials`).

### 2. ArgoCD Application shows `Unknown` Sync Status
This usually means ArgoCD cannot read the Helm chart from ECR or cannot read the Git repository.
```bash
# Check the specific error message
kubectl describe application <app-name> -n argocd

# Check the Repo Server logs for network/auth errors
kubectl logs -n argocd deploy/argocd-repo-server --tail=100
```
* **Private Git Repo?** If your GitHub repo is private, you must add a Personal Access Token (PAT) to ArgoCD as a Repository Credential.
* **Missing Chart?** Ensure the chart version listed in `chart-tags.yaml` actually exists in ECR! Check the AWS Console.

### 3. API Pod is stuck in `CrashLoopBackOff`
This happens if the application crashes on startup (e.g., missing database URL), or if the Kubernetes Health Probes are failing.
```bash
# Check the application logs for stack traces
kubectl logs -n <namespace> <pod-name>

# Check the probe failure events
kubectl describe pod -n <namespace> <pod-name>
```
*Note: `messenger-api` is a WebSocket server and does not have an `/api/health` REST endpoint. Its health probe is deliberately configured to hit `/socket.io/socket.io.js` in `argocd/apps/values.yaml`.*

### 4. MetalLB External IP is `<pending>`
If Traefik isn't getting an IP address:
```bash
kubectl get svc -n traefik-ingress traefik-service
```
This means the IP pool defined in `helm/metallb/values.yaml` is exhausted or misconfigured. Ensure the IP range in that file is valid and routable on your VM's local network subnets.
