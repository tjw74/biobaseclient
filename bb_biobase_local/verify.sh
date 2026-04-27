#!/usr/bin/env bash
# Quick checks: gateway container, host port, HTTP 200. Run from bb_biobase_local/.
set -euo pipefail
PORT="${BIOBASE_LOCAL_PORT:-8880}"
if [[ -f .env ]]; then
  # shellcheck source=/dev/null
  set -a && source .env && set +a
  PORT="${BIOBASE_LOCAL_PORT:-$PORT}"
fi

echo "=== Biobase gateway (host port ${PORT}) ==="
if docker ps --format '{{.Names}}' | grep -qx bb_biobase_local; then
  echo "OK: container bb_biobase_local is running"
  docker ps --filter name=bb_biobase_local --format '    {{.Ports}}'
else
  echo "MISSING: start with: cd bb_biobase_local && docker compose up -d"
fi

if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
  echo "OK: something is listening on :${PORT}"
else
  echo "WARN: nothing listening on :${PORT} (compose not up or wrong port?)"
fi

code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:${PORT}/" || echo "000")
if [[ "$code" == "200" ]]; then
  echo "OK: GET http://127.0.0.1:${PORT}/ -> 200"
else
  echo "FAIL: GET http://127.0.0.1:${PORT}/ -> HTTP ${code}"
fi

IP="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1 || true)"
echo ""
echo "=== From another device on the LAN ==="
if [[ -n "$IP" ]]; then
  echo "  Open:  http://${IP}:${PORT}/"
  echo "  Grafana path:  http://${IP}:${PORT}/bb/"
else
  echo "  (Could not detect LAN IP — use the Docker host's address on your network.)"
fi
echo ""
echo "NOTE: http://<host>:${PORT}/ is this hub. Port 80 without :${PORT} is often a different service."
echo "Grafana (direct port 3003): still available; hub uses /bb/ on ${PORT}."
