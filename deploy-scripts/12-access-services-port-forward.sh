#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/tmp/nitroberry-port-forwards"
mkdir -p "${LOG_DIR}"

echo "=================================================="
echo "12 - Port-Forward Infra Services (background)"
echo "=================================================="
echo "Logs: ${LOG_DIR}/*.log"
echo "Use 'jobs -l' or 'ps aux | grep port-forward' to see what's running."
echo "Use 'kill <pid>' to stop an individual forward."
echo

start_forward() {
  local name="$1"
  local svc="$2"
  local ns="$3"
  local ports="$4"

  nohup kubectl port-forward "svc/${svc}" -n "${ns}" "${ports}" \
    > "${LOG_DIR}/${name}.log" 2>&1 &
  disown
  echo "  ${name}: svc/${svc} -n ${ns} -> ${ports}  (pid $!, log: ${LOG_DIR}/${name}.log)"
}

start_forward "traefik"   "traefik-service"   "traefik-ingress"    "8081:80"
start_forward "postgres"  "postgres-service"  "database-namespace" "5432:5432"
start_forward "redis"     "redis-service"     "database-namespace" "6379:6379"
start_forward "pgbouncer" "pgbouncer-service" "database-namespace" "6432:6432"

sleep 2

echo
echo "--- Quick check: Traefik should respond (a 404 is expected, no routes configured) ---"
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8081/ || echo "Traefik not reachable yet - check ${LOG_DIR}/traefik.log"

echo
echo "Checklist:"
echo "  [ ] Traefik returns an HTTP status (404 is fine)"
echo "  [ ] Postgres/Redis/PgBouncer ports forward without connection errors"
echo "      (test: nc -zv localhost 5432 / 6379 / 6432)"
echo
echo "These forwards keep running after this script exits (backgrounded + disowned)."
echo "Stop them all with: pkill -f 'kubectl port-forward'"
