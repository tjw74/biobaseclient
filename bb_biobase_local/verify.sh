#!/usr/bin/env bash
# Quick checks: gateway container, host port, HTTP 200. Run from bb_biobase_local/.
set -euo pipefail
PORT="${BIOBASE_LOCAL_PORT:-8880}"
if [[ -f .env ]]; then
  # shellcheck source=/dev/null
  set -a && source .env && set +a
  PORT="${BIOBASE_LOCAL_PORT:-$PORT}"
fi

echo "=== biobase.local gateway (host port ${PORT}) ==="
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

echo ""
echo "=== name biobase.local ==="
if getent ahosts biobase.local >/dev/null 2>&1; then
  echo "OK: name resolves:"
  getent ahosts biobase.local | head -3
else
  echo "NOT RESOLVING: Firefox 'Server Not Found' is usually this."
  echo "  Option A — mDNS on the Docker host: ./mdns/publish-biobase-local.sh (keep running) or systemd unit"
  echo "  Option B — /etc/hosts on the machine where the browser runs:"
  echo "      same host as Docker:  127.0.0.1 biobase.local"
  echo "      other LAN device:     <this-host-LAN-IP> biobase.local"
  IP="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1 || true)"
  if [[ -n "$IP" ]]; then
    echo "      (this host’s LAN IP looks like: ${IP})"
  fi
  echo "  Then open: http://biobase.local:${PORT}/"
fi
