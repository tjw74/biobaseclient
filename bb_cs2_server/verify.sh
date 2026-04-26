#!/usr/bin/env bash
# Self-check: container up, TCP to game port, RCON + Metamod CS2KZ plugins.
# Run on the host that runs Docker; set RCON_HOST if checking from another machine.
# Usage: ./verify.sh    RCON_PASSWORD=secret ./verify.sh
set -u

CONTAINER_NAME="${CS2_CONTAINER_NAME:-bb_cs2_server}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${DIR}/rcon.sh"

fail=0
ok()  { echo "[OK]   $*"; }
bad() { echo "[FAIL] $*"; fail=1; }

echo "=== biobase CS2 server verification ==="
echo

if ! command -v docker >/dev/null 2>&1; then
	bad "docker not in PATH"
	exit 1
fi

if ! docker info >/dev/null 2>&1; then
	bad "docker not usable (daemon or permissions)"
	exit 1
fi

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
	ok "Container ${CONTAINER_NAME} is running"
else
	bad "Container ${CONTAINER_NAME} not running (docker ps)"
fi

if [[ ! -x "${DIR}/bin/mcrcon" ]]; then
	bad "Missing ${DIR}/bin/mcrcon"
fi

HOST="${RCON_HOST:-127.0.0.1}"
PORT="${RCON_PORT:-27015}"

if timeout 2 bash -c "echo >/dev/tcp/${HOST}/${PORT}" 2>/dev/null; then
	ok "TCP ${HOST}:${PORT} open (RCON)"
else
	bad "TCP ${HOST}:${PORT} not reachable"
fi

if [[ -x "$R" && -x "${DIR}/bin/mcrcon" ]]; then
	meta="$("$R" "meta list" 2>&1 || true)"
	if echo "$meta" | grep -q "CS2KZ"; then
		ok "Metamod lists CS2KZ (plugins loaded)"
		echo "$meta" | sed 's/\x1b\[[0-9;]*m//g' | head -6
	else
		bad "No CS2KZ in meta list"
		echo "$meta" | head -20
	fi

	st="$("$R" "status" 2>&1 || true)"
	if echo "$st" | grep -q "Server:"; then
		ok "RCON status response"
		echo "$st" | sed 's/\x1b\[[0-9;]*m//g' | head -5
	else
		bad "Bad RCON status"
		echo "$st" | head -10
	fi
else
	bad "Skipped RCON (missing rcon.sh or mcrcon)"
fi

echo
if [[ "$fail" -ne 0 ]]; then
	echo "=== RESULT: FAILED ==="
	exit 1
fi
echo "=== RESULT: OK ==="
exit 0
