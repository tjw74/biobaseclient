#!/usr/bin/env bash
# Back-compat — use bots_start.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bots_start.sh" "$@"
