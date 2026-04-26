#!/usr/bin/env sh
# Publish mDNS A record for biobase.local (single-label: biobase) on the main IPv4 default route.
# Requires: avahi-daemon, avahi-utils (avahi-publish).
# Stop with Ctrl+C; for always-on, use the systemd unit in this directory.
set -eu

if ! command -v avahi-publish >/dev/null 2>&1; then
  echo "avahi-publish not found. Install avahi (e.g. avahi-daemon + avahi-utils on Debian/Ubuntu)." >&2
  exit 1
fi

# Prefer default-route source address (outbound 1.1.1.1/8.8.8.8); fallback: first private IPv4.
IP=${BIOBASE_LOCAL_IP:-}
if [ -z "$IP" ]; then
  if command -v ip >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    IP=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)
  fi
fi
if [ -z "$IP" ] && command -v hostname >/dev/null 2>&1; then
  for x in $(hostname -I 2>/dev/null); do
    case "$x" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
      IP=$x
      break
      ;;
    esac
  done
fi
if [ -z "$IP" ]; then
  echo "Could not determine LAN IPv4. Set BIOBASE_LOCAL_IP=192.168.x.x" >&2
  exit 1
fi

# -R: replace; name without .local (avahi appends mDNS TLD)
echo "Advertising biobase.local -> $IP (press Ctrl+C to stop)"
exec avahi-publish -a -R biobase "$IP"
