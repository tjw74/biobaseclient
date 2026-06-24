#!/usr/bin/env bash
# One-shot: chmod +x the rebuild helper and stage it in Git as mode 100755 (no execute bit needed to run this file).
# Usage (from repo root):  bash grant_rebuild_script_exec_bit.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
TARGET="rebuild_cs2_and_run_map_position_test.sh"
if [[ ! -f "$TARGET" ]]; then
	echo "missing $ROOT/$TARGET" >&2
	exit 1
fi
chmod +x "$TARGET"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git add --chmod=+x "$TARGET"
	git ls-files --stage "$TARGET"
	git status -sb -- "$TARGET"
else
	echo "not a git repo; chmod +x only"
fi
