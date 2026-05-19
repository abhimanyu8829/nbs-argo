#!/bin/bash

# Port forwarding for NitroBerry services
# This script sets up port-forwarding so you can curl the services locally

echo "Setting up port forwarding for NitroBerry services..."
echo ""
echo "Services available:"
echo "  http://localhost:8081 - Traefik Ingress"
echo "  http://localhost:5432 - PostgreSQL (host: localhost)"
echo "  http://localhost:6379 - Redis"
echo "  http://localhost:6432 - PgBouncer"
echo "  http://localhost:8080 - ArgoCD UI"
echo "  http://localhost:8000 - Traefik Dashboard"
echo ""

# Start port forwarding in background
kubectl port-forward svc/traefik-service -n traefik-ingress 8081:80 &
TRAEFIK_PID=$!
echo "✓ Traefik forwarded to 8081 (PID: $TRAEFIK_PID)"

kubectl port-forward svc/postgres-service -n database-namespace 5432:5432 &
PG_PID=$!
echo "✓ PostgreSQL forwarded to 5432 (PID: $PG_PID)"

kubectl port-forward svc/redis-service -n database-namespace 6379:6379 &
REDIS_PID=$!
echo "✓ Redis forwarded to 6379 (PID: $REDIS_PID)"

kubectl port-forward svc/pgbouncer-service -n database-namespace 6432:6432 &
PGB_PID=$!
echo "✓ PgBouncer forwarded to 6432 (PID: $PGB_PID)"

kubectl port-forward svc/argocd-server -n argocd 8080:443 &
ARGOCD_PID=$!
echo "✓ ArgoCD UI forwarded to 8080 (PID: $ARGOCD_PID)"

echo ""
echo "All services are accessible! Test with curl:"
echo ""
echo "  curl http://localhost:8081/"
echo "  curl -k https://localhost:8080/"
echo ""
echo "Press Enter to stop all port forwarding..."
read

# Cleanup
kill $TRAEFIK_PID $PG_PID $REDIS_PID $PGB_PID $ARGOCD_PID 2>/dev/null
echo "Port forwarding stopped."
