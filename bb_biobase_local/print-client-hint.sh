#!/usr/bin/env sh
# Run on the Biobase **host** to print the lines a browser machine needs to reach the hub.
# "Server not found" on http://biobase.local:8880 almost always means: no IP for the name, or
# the client is not on the same LAN / firewall blocks 8880.
set -eu

ip="${BIOBASE_LAN_IP:-}"
if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
  # shellcheck disable=SC2016
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)
fi
if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
port="${BIOBASE_LOCAL_PORT:-8880}"

echo "=== Biobase browser hint (this host) ==="
echo "Detected LAN IP (for /etc/hosts on the machine running Firefox): ${ip:-<unknown>}"
echo ""
echo "1) On the **same computer** that runs Docker, add to /etc/hosts:"
echo "   127.0.0.1   biobase.local"
echo "   Open:  http://biobase.local:${port}/"
echo ""
echo "2) On a **phone / laptop** on the same Wi‑Fi, add to /etc/hosts (or Windows hosts file):"
echo "   ${ip:-192.168.x.x}   biobase.local"
echo "   Open:  http://biobase.local:${port}/"
echo ""
echo "3) mDNS: on this host, keep running ./mdns/publish-biobase-local.sh (or systemd) so"
echo "   some clients resolve biobase.local without a hosts file."
echo ""
echo "4) Firewall on **this** host: allow TCP ${port} from the LAN, e.g."
echo "   sudo ufw allow ${port}/tcp   # or iptables / firewalld as appropriate"
echo ""
echo "5) Firefox: if the name still fails, set about:config"
echo "   network.dns.localDomains = biobase.local"
echo "   (after hosts or mDNS is in place, or for split-DNS / DoH issues)."
