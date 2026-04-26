#!/usr/bin/env bash
# Idempotent: register biobase.local via Avahi (address record + optional _http SRV) without
# editing /etc/avahi/avahi-daemon.conf or any other app’s mDNS data.
# Usage:  sudo ./install-biobase-mdns.sh
# Env:   BIOBASE_LOCAL_PORT (default 8880) — must match bb_biobase_local docker published port
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${BIOBASE_LOCAL_PORT:-8880}"
UNIT_SRC="${DIR}/biobase-mdns.service"
PUBLISH_SRC="${DIR}/publish-biobase-local.sh"
HTTP_TEMPLATE="${DIR}/biobase-http.service.in"
AVAHISVC="/etc/avahi/services/bb-biobase-hub.service"
PUBLISH_DST="/usr/local/bin/biobase-mdns-publish"
UNIT_DST="/etc/systemd/system/biobase-mdns.service"
DEFAULT_SRC="${DIR}/biobase-mdns.default"
DEFAULT_DST="/etc/default/biobase-mdns"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
  echo "avahi-daemon is not active. Install and start: apt install avahi-daemon; systemctl enable --now avahi-daemon" >&2
  exit 1
fi
[ -f "$PUBLISH_SRC" ] && [ -f "$UNIT_SRC" ] || { echo "Missing files in $DIR" >&2; exit 1; }
command -v avahi-publish >/dev/null 2>&1 || {
  echo "avahi-publish not found. Install: apt install avahi-utils" >&2
  exit 1
}

install -d /usr/local/bin /etc/avahi/services
install -m 0755 "$PUBLISH_SRC" "$PUBLISH_DST"
install -m 0644 "$UNIT_SRC" "$UNIT_DST"
if [ -f "$DEFAULT_SRC" ] && [ ! -f "$DEFAULT_DST" ]; then
  install -m 0644 "$DEFAULT_SRC" "$DEFAULT_DST"
  echo "Installed $DEFAULT_DST (edit to set BIOBASE_LOCAL_IP if needed)"
fi
if [ -f "$HTTP_TEMPLATE" ]; then
  sed "s/@@PORT@@/${PORT}/g" "$HTTP_TEMPLATE" > "$AVAHISVC"
  chmod 0644 "$AVAHISVC"
  echo "Installed Avahi service advertisement: $AVAHISVC (HTTP on :${PORT})"
fi
systemctl daemon-reload
systemctl enable --now biobase-mdns.service
# Pick up new/updated service file without clobbering other /etc/avahi/services/*
if systemctl reload avahi-daemon 2>/dev/null; then
  echo "Reloaded avahi-daemon."
else
  systemctl restart avahi-daemon
  echo "Restarted avahi-daemon (reload not available)."
fi
echo
echo "Done. This host should now advertise **biobase.local** -> (LAN IPv4)."
echo "Open:  http://biobase.local:${PORT}/   (and /bb/, /loki/, /cs2/ on the same origin)"
echo "Check: systemctl status biobase-mdns.service"
if command -v avahi-browse >/dev/null 2>&1; then
  echo "      avahi-browse -a -r 2>/dev/null | head -20"
fi
