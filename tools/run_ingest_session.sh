#!/usr/bin/env bash
# Alias for run_kz_session.sh (ingest naming). See tools/run_kz_session.sh for behavior.
# Usage from repo root:  DURATION_SEC=60 ./tools/run_ingest_session.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/run_kz_session.sh" "$@"
