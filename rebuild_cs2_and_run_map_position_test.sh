#!/usr/bin/env bash
# Rebuild bb_cs2_server (+ bb_cs2_control), recreate containers, then run tools/test_map_position.py.
# Pass-through: any args go to test_map_position.py (e.g. --duration 120).
#
# If ./script.sh gives "Permission denied", run once:
#   chmod +x rebuild_cs2_and_run_map_position_test.sh
# or invoke without execute bit:
#   bash rebuild_cs2_and_run_map_position_test.sh
# To stage execute permission in Git (avoids update-index on untracked files):
#   bash grant_rebuild_script_exec_bit.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$ROOT/bb_cs2_server"
CS2_CONTROL_URL="${CS2_CONTROL_URL:-http://127.0.0.1:8765}"
RCON_READY_TIMEOUT="${RCON_READY_TIMEOUT:-180}"

cd "$COMPOSE_DIR"
docker compose build bb_cs2_server bb_cs2_control

# Remove stale pre.sh from the volume so entry.sh always copies /etc/pre.sh from the new image.
# (entry.sh only copies it when the file is absent; the volume persists between rebuilds.)
docker run --rm -v bb_cs2_server_cs2_data:/data alpine sh -c 'rm -f /data/pre.sh /data/post.sh' 2>/dev/null || true

docker compose up -d bb_cs2_server bb_cs2_control --force-recreate

echo "Waiting for CS2 RCON to be ready (timeout ${RCON_READY_TIMEOUT}s) …"
deadline=$(( $(date +%s) + RCON_READY_TIMEOUT ))
while true; do
    if curl -sf "${CS2_CONTROL_URL}/api/status" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('rcon_ok') else 1)" 2>/dev/null; then
        echo "CS2 RCON ready."
        break
    fi
    remaining=$(( deadline - $(date +%s) ))
    if [[ $remaining -le 0 ]]; then
        echo "ERROR: CS2 RCON not ready after ${RCON_READY_TIMEOUT}s — check: docker logs bb_cs2_server" >&2
        exit 1
    fi
    echo "  … waiting (${remaining}s left)"
    sleep 5
done

exec python3 "$ROOT/tools/test_map_position.py" "$@"
