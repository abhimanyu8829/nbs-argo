#!/bin/bash

# ArgoCD Access Guide

echo "=========================================="
echo "NitroBerry ArgoCD Access Information"
echo "=========================================="
echo ""

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "NOT_AVAILABLE")

echo "ArgoCD UI URL:"
echo "  https://localhost:8080/"
echo ""
echo "⚠️  Browser may show certificate warning - click 'Advanced' → 'Proceed'"
echo ""
echo "Login Credentials:"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASS"
echo ""
echo "=========================================="
echo ""
echo "Port Forwarding Status:"
kubectl get svc -n argocd argocd-server
echo ""
echo "=========================================="
echo ""
echo "To login via ArgoCD CLI:"
echo "  argocd login localhost:8080 --username admin --password $ARGOCD_PASS --insecure"
echo ""
