# `biobase.local` — LAN admin hub

Single entry point in the browser: **http://biobase.local** (or `http://<host-ip>:80`) after you bring this stack and mDNS up.

## 1. Network

- Create `biobase_internal` first (from `bb_monitor_loki`, or any stack that creates it with that name).
- Other services must be on the same network: `bb_monitor_grafana`, `bb_monitor_loki`, `bb_cs2_control` (e.g. `bb_cs2_server/docker-compose` plus monitor stacks).

## 2. mDNS (host)

On the **machine running Docker**, install Avahi and either:

- **Foreground:** `chmod +x mdns/publish-biobase-local.sh && ./mdns/publish-biobase-local.sh`, or
- **systemd:** copy `mdns/publish-biobase-local.sh` to `/usr/local/bin/`, add `mdns/biobase-mdns.service`, enable the unit (comments inside the file).

Optional: set `BIOBASE_LOCAL_IP` if the script’s IP guess is wrong. Clients on the same LAN can then resolve **biobase.local**.

**Alternative** without a script: set the host’s machine name to `biobase` so Avahi advertises `biobase.local` (depends on distribution).

## 3. Nginx gateway

```bash
cd bb_biobase_local
docker compose up -d
```

- **80** (default) → static index, `/bb/` → Grafana, `/loki/` → Loki, `/cs2/` → CS2 control.
- **Prometheus** stays on host port **19090**; the home page links there by hostname and port (same pattern as before, now from one landing page).

Override listen port: `BIOBASE_LOCAL_PORT=8080 docker compose up -d`.

## 4. Grafana URL

When you use the hostname `biobase.local` (or this nginx proxy) for Grafana, set in `bb_monitor_grafana` (or your `.env` there):

```env
GF_SERVER_ROOT_URL=http://biobase.local/bb/
```

(Adjust scheme/host if you use another name or add TLS later.) Restart Grafana after changing it.

## 5. What stays separate

- CS2 and RCON are unchanged; this layer only unifies **discovery and navigation** (per `../info.md`).
- Remote access from other networks is out of scope; use VPN or a tunnel.
