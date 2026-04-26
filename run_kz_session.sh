#!/usr/bin/env bash
# One-shot: RCON time limits, start bb_data_collection session, start bots, wait, print summary.
# Usage (from biobase repo root):
#   DURATION_SEC=300 ./run_kz_session.sh
#   DURATION_SEC=25 ./run_kz_session.sh    # short smoke
#
# Prereq: docker stacks — bb_client (data collection + postgres), bb_cs2_server, bb_monitor_loki, biobase_internal.
# Env: DATA_URL (default http://127.0.0.1:28080), CS2_URL, optional BB_CS2_CONTROL_TOKEN
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DURATION_SEC="${DURATION_SEC:-300}"
RCON_SH="${ROOT}/bb_cs2_server/short_match_rcon.sh"
DATA_URL="${DATA_URL:-http://127.0.0.1:28080}"
CS2_URL="${CS2_URL:-http://127.0.0.1:8765}"
export DURATION_SEC
export LABEL="kz-data-${DURATION_SEC}s"
TOKEN="${BB_CS2_CONTROL_TOKEN:-${CS2_CONTROL_TOKEN:-}}"

if [[ -x "$RCON_SH" ]]; then
	echo "=== RCON: short map / long rounds ==="
	(bash "$RCON_SH") || true
else
	echo "WARN: short_match_rcon.sh missing, skip RCON preset"
fi

echo "=== Start ingest session ($DURATION_SEC s) ==="
body=$(
	python3 -c "import os,json; print(json.dumps({
		'duration_seconds': int(os.environ['DURATION_SEC']),
		'rcon_interval_seconds': 5.0,
		'label': os.environ.get('LABEL'),
	}))"
)
start=$(curl -sS -X POST "$DATA_URL/v1/sessions" -H "Content-Type: application/json" -d "$body")
echo "$start"
sid=$(echo "$start" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id') or '')")
if [[ -z "$sid" ]]; then
	echo "Failed to start session" >&2
	exit 1
fi

post_bots() {
	if [[ -n "$TOKEN" ]]; then
		curl -sS -X POST "$CS2_URL/api/bots/start" -H "X-Api-Key: $TOKEN" -H "Content-Type: application/json" -d '{}'
	else
		curl -sS -X POST "$CS2_URL/api/bots/start" -H "Content-Type: application/json" -d '{}'
	fi
}

echo "=== Bot game start (RCON) ==="
post_bots || true
echo

echo "=== Waiting ${DURATION_SEC}s (collection + server logs) ==="
sleep "$DURATION_SEC"

echo "=== Session status (poll until complete) ==="
for _ in $(seq 1 40); do
	st=$(curl -sS "$DATA_URL/v1/sessions/$sid")
	stv=$(echo "$st" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))")
	echo "  $stv"
	if [[ "$stv" == "complete" ]]; then
		break
	fi
	if [[ "$stv" == "failed" ]]; then
		echo "$st" >&2
		exit 1
	fi
	sleep 2
done

echo
echo "=== TEXT SUMMARY ==="
curl -sS "$DATA_URL/v1/sessions/$sid/summary" -H "Accept: text/plain" | head -80

echo
echo "=== Full JSON: $DATA_URL/v1/sessions/$sid/summary ==="
