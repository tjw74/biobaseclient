#!/usr/bin/env bash
# Optional RCON preset before a data-collection session: ~5 min map, long rounds (KZ/bot testing).
# Run on the host with bb_cs2_server up:  ./short_match_rcon.sh
# Set RCON_HOST / RCON_PORT / RCON_PASSWORD or CS2_RCONPW to match docker-compose.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${DIR}/rcon.sh"
[[ -x "$R" ]] || { echo "missing $R"; exit 1; }

echo "bb_cs2_server: applying short-session friendly cvars (ignore unknown errors)"
r() { "$R" "$@" 2>&1 | head -1 || true; }

r mp_warmup_end
r mp_freezetime 3
r mp_timelimit 5
r mp_roundtime 5
r mp_roundtime_defuse 5
r mp_halftime 0
echo "Done. If the server is not on a defuse map, some cvars are no-ops — still OK for KZ."
