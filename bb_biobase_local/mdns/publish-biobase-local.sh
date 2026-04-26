#!/usr/bin/env sh
# Publish mDNS A record: ${BIOBASE_MDNS_NAME}.local -> LAN IPv4 (default name: biobase).
# Does not modify avahi-daemon.conf. Requires: avahi-daemon, avahi-utils.
# See install-biobase-mdns.sh for a systemd one-shot; optional env: /etc/default/biobase-mdns
set -eu

if ! command -v avahi-publish >/dev/null 2>&1; then
  echo "avahi-publish not found. Install avahi-utils (e.g. apt install avahi-utils)." >&2
  exit 1
fi

NAME=${BIOBASE_MDNS_NAME:-biobase}
# Single DNS label; avahi will advertise NAME.local
case "$NAME" in
*.* | *:* | "") echo "BIOBASE_MDNS_NAME must be a single label (e.g. biobase), got: $NAME" >&2; exit 1 ;;
esac

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
  echo "Could not determine LAN IPv4. Set BIOBASE_LOCAL_IP in the environment or /etc/default/biobase-mdns" >&2
  exit 1
fi

# -R: replace existing; avahi appends .local
if [ -t 1 ] && [ -t 2 ]; then
  echo "Advertising ${NAME}.local -> $IP (Ctrl+C to stop; use systemd for always-on)" >&2
fi
exec avahi-publish -a -R "$NAME" "$IP"
