#!/bin/bash

# Test NitroBerry services by curling them
# This shows that each service is deployed and responding

echo "=========================================="
echo "Testing NitroBerry Deployment"
echo "=========================================="
echo ""

echo "Step 1: Check all pods status..."
echo "---"
kubectl get pods -A | grep -E 'auth|cockpit|messenger|social|task|workflow|postgres|redis|pgbouncer|traefik'
echo ""

echo "Step 2: Test Infrastructure Services..."
echo "---"

echo "PostgreSQL Pod Info:"
kubectl get pod postgres-0 -n database-namespace -o wide

echo ""
echo "Redis Pod Info:"
kubectl get pod -n database-namespace -l app=redis -o wide

echo ""
echo "PgBouncer Pod Info (both replicas):"
kubectl get pods -n database-namespace -l app=pgbouncer -o wide

echo ""
echo "Traefik Pod Info:"
kubectl get pod -n traefik-ingress -l app=traefik -o wide

echo ""
echo "=========================================="
echo "Container Logs - Check for errors:"
echo "=========================================="
echo ""

echo "Traefik logs:"
kubectl logs -n traefik-ingress -l app=traefik --tail=5

echo ""
echo "PostgreSQL logs:"
kubectl logs -n database-namespace postgres-0 --tail=5

echo ""
echo "Redis logs:"
kubectl logs -n database-namespace -l app=redis --tail=5

echo ""
echo "=========================================="
echo "To access services:"
echo "=========================================="
echo ""
echo "Run this to set up port forwarding:"
echo "  bash ./script/port-forward.sh"
echo ""
echo "Then test with curl:"
echo "  curl http://localhost:8081/"
echo ""
echo "View ArgoCD UI:"
echo "  open http://localhost:8080/"
echo "  (username: admin, password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d))"
echo ""
