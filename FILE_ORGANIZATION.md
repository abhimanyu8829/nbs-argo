# NitroBerry Platform: File Organization & Deployment Quick Start

## 📋 Quick Decision Matrix

**Choose your deployment path:**

```
┌─────────────────────────────────────────────────────────┐
│  Production Deployment (Cloud VM - AWS EC2, etc)       │
├─────────────────────────────────────────────────────────┤
│ • Real AWS ECR credentials required                    │
│ • Full security configuration                          │
│ • Production-grade persistence volumes                 │
│ • Estimated time: 15-30 minutes                        │
│ • Entry point: README.md → Production Deployment Guide│
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Local Testing (WSL Ubuntu with Docker)                │
├─────────────────────────────────────────────────────────┤
│ • Dummy credentials (no AWS needed)                    │
│ • Perfect for development & testing                   │
│ • Ephemeral data (EmptyDir volumes)                    │
│ • Estimated time: 5-10 minutes                         │
│ • Entry point: README.md → Local Testing Guide        │
└─────────────────────────────────────────────────────────┘
```

---

## 🗂️ File Organization Reference

### ✅ USEFUL - Core Files (Use for Both Prod & Local)

#### Infrastructure as Code (IaC)
| File | Purpose | Used By |
|------|---------|---------|
| `argocd/root-app.yaml` | ⭐ **MAIN ENTRY POINT** - Root ArgoCD application | Both |
| `argocd/apps/Chart.yaml` | Helm chart generator for child applications | Both |
| `argocd/apps/values.yaml` | ⭐ **CRITICAL** - All microservice configs | Both |
| `argocd/apps/chart-tags.yaml` | Docker image versions for all 19 services | Both |
| `argocd/apps/templates/applications.yaml` | Generates individual applications | Both |
| `helm/*/Chart.yaml` | Infrastructure Helm chart metadata | Both |
| `helm/*/values.yaml` | Infrastructure configuration (MetalLB IPs, etc) | Both |
| `helm/*/templates/*` | Kubernetes manifests | Both |
| `README.md` | 📖 Complete deployment guide | Both |
| `DEPLOYMENT_SUMMARY.md` | Pod status & access information | Both |
| `.gitignore` | Git ignore rules | Both |

---

### ✅ USEFUL-PROD - Production Only

| File | Purpose | Use Case |
|------|---------|----------|
| `script/installation/setup-vm.sh` | 🔧 Phase 1: Master bootstrap (kubeadm, k8s init, ArgoCD) | Prod Only |
| `script/deploy-production.sh` | 🔧 Phase 2: Production verification & ECR setup | Prod Only |
| `script/push-infra-charts.sh` | 📦 Pushes Helm charts to AWS ECR | Prod Only |
| `script/installation/ecr-helper.yaml` | 🔄 CronJob to refresh ECR tokens automatically | Prod Only |

**When to use these:**
1. First time production deployment: Use `setup-vm.sh` then `deploy-production.sh`
2. Refresh ECR credentials: Re-run `deploy-production.sh`
3. Update infrastructure charts: Run `push-infra-charts.sh` before committing

---

### ✅ USEFUL-LOCAL - Local Testing Only

| File | Purpose | Use Case |
|------|---------|----------|
| `script/deploy-wsl-local.sh` | ✨ **NEW** One-command local deployment | Local Only |
| `script/port-forward.sh` | 🔌 Port forwarding setup for service access | Local Only |
| `script/test-deployment.sh` | ✓ Verification script (pods, logs, status) | Local Only |
| `ACCESS_ARGOCD.sh` | 🔑 Display ArgoCD credentials | Local Only |

**Quick start for local testing:**
```bash
cd NitroBerry-Platform
chmod +x script/deploy-wsl-local.sh
sudo script/deploy-wsl-local.sh  # Waits 10-15 min
bash script/test-deployment.sh    # Verify everything
bash script/port-forward.sh       # Access services
```

---

### ❌ NOT USEFUL - Archive/Review

| File | Status | Action |
|------|--------|--------|
| `reviewcomments.md` | Archived | Can be deleted |

---

## 🎯 Deployment Workflows

### Scenario 1: First Time Production Deployment

```bash
# Step 1: On your local machine
git clone https://github.com/dushyantajangid/NitroBerry-Platform.git
cd NitroBerry-Platform
./script/push-infra-charts.sh ap-south-1

# Step 2: SSH into production VM
ssh ubuntu@<VM_PUBLIC_IP>
cd NitroBerry-Platform
export AWS_REGION=ap-south-1

# Step 3: Execute bootstrap (Phase 1)
chmod +x script/installation/setup-vm.sh
./script/installation/setup-vm.sh    # ⏱️ 5-15 min

# Step 4: Verify deployment (Phase 2)  
chmod +x script/deploy-production.sh
./script/deploy-production.sh         # ⏱️ 3-10 min

# Result: All 19 pods running + ArgoCD synced ✅
```

### Scenario 2: Local Testing / Development

```bash
# On Windows PowerShell
wsl -d Ubuntu bash
cd /mnt/c/Users/DELL-OS/OneDrive/Desktop/argocd-nbs/NitroBerry-Platform/NitroBerry-Platform

# Single command deploys everything
chmod +x script/deploy-wsl-local.sh
sudo script/deploy-wsl-local.sh       # ⏱️ 10-15 min

# Verify & access
bash script/test-deployment.sh
bash script/port-forward.sh

# Access https://localhost:8080/ → All 19 pods running ✅
```

### Scenario 3: Update Microservice Version

```bash
# Edit values
vim argocd/apps/chart-tags.yaml
# Change: auth-api: "0.0.7"

# Commit & push
git add argocd/apps/chart-tags.yaml
git commit -m "chore: bump auth-api to v0.0.7"
git push origin argocdTest

# ArgoCD auto-detects within 3 minutes (or manually refresh):
kubectl annotate application -n argocd nitroberry-platform-apps argocd.argoproj.io/refresh=hard --overwrite

# Result: Rolling update of auth-api pods ✅ (zero downtime)
```

### Scenario 4: Recover from ECR Token Expiration (Prod)

```bash
# This fixes ImagePullBackOff errors caused by expired ECR credentials
./script/deploy-production.sh

# What it does:
# ✓ Refreshes ECR tokens in all namespaces
# ✓ Updates image pull secrets
# ✓ Forces ArgoCD re-sync
# ✓ Waits for all pods to become Ready
# ✓ Reports final health status
```

---

## 📊 19 Pods Deployed Summary

### Infrastructure (5 pods)
```
database-namespace:
  ├── postgres-0 (1 pod)
  ├── redis-* (1 pod)
  └── pgbouncer-* (2 pods)

traefik-ingress:
  └── traefik-* (1 pod)

metallb-system:
  └── controller + speaker (2 pods)
```

### Microservices (13 pods)
```
auth-namespace:
  ├── auth-api (1 pod)
  └── auth-worker (1 pod)

cockpit-namespace:
  ├── cockpit-api (1 pod)
  └── cockpit-worker (1 pod)

messenger-namespace:
  └── messenger-api (1 pod)

social-namespace:
  ├── social-api (1 pod)
  └── social-worker (1 pod)

task-namespace:
  ├── task-api (1 pod)
  └── task-worker (1 pod)

vault-namespace:
  ├── vault-api (1 pod)
  └── vault-worker (1 pod)

workflow-namespace:
  ├── workflow-api (1 pod)
  └── workflow-worker (1 pod)
```

---

## 🔐 Credentials Reference

### Local Testing
```
PostgreSQL:
  Host: localhost:5432
  User: postgres
  Password: nitroberry-local-pass

ArgoCD:
  URL: https://localhost:8080
  Username: admin
  Password: (run: bash script/ACCESS_ARGOCD.sh)
```

### Production
```
PostgreSQL:
  Host: postgres-service.database-namespace.svc.cluster.local:5432
  User: postgres
  Password: (from setup-vm.sh output or AWS Secrets Manager)

ArgoCD:
  URL: https://<VM_PUBLIC_IP>:8080 (with port-forward) or https://vm-ip:8080
  Username: admin
  Password: (saved at end of setup-vm.sh)
```

---

## ✨ What's New in This Update

1. **README.md Restructured** 
   - Clear separation: Production vs Local Testing
   - Step-by-step guides for both paths
   - From SSH login to full deployment

2. **New Local Testing Script**
   - `script/deploy-wsl-local.sh` - One-command WSL deployment
   - Perfect for CI/CD, development, validation

3. **File Organization Documented**
   - Marked files as USEFUL / USEFUL-PROD / USEFUL-LOCAL / NOT USEFUL
   - Clear purpose for each file
   - Organized by usage

4. **Enhanced Documentation**
   - Multiple scenario workflows
   - Troubleshooting section
   - Day-2 operations guide
   - Service access matrix

---

## 🚀 Getting Started

**Pick your path:**

### 👉 I want to deploy to production
→ Read: `README.md` → **Production Deployment Guide** section  
→ Execute: `script/installation/setup-vm.sh` + `script/deploy-production.sh`

### 👉 I want to test locally
→ Read: `README.md` → **Local Testing Deployment Guide** section  
→ Execute: `script/deploy-wsl-local.sh`

### 👉 I want to understand the architecture
→ Read: `README.md` → **Architecture** section  
→ Review: `argocd/root-app.yaml` and `argocd/apps/values.yaml`

### 👉 I have a production issue
→ Read: `README.md` → **Troubleshooting** section  
→ Execute: `./script/deploy-production.sh` (safe to re-run)

---

**Last Updated:** May 19, 2026  
**Status:** ✅ All 19 NitroBerry pods deployable in both production and local testing environments
