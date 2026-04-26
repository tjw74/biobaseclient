# `biobase.local` — LAN admin hub

Single entry point in the browser: **http://biobase.local:8880/** (default port; see below) after you bring this stack up and make the name resolve.

## 1. Network

- Create `biobase_internal` first (from `bb_monitor_loki`, or any stack that creates it with that name).
- Other services must be on the same network: `bb_monitor_grafana`, `bb_monitor_loki`, `bb_cs2_control` (e.g. `bb_cs2_server/docker-compose` plus monitor stacks).

## 2. Start the gateway

```bash
cd bb_biobase_local
cp -n .env.example .env   # optional; default port 8880
docker compose up -d
./verify.sh
```

**Port 8880 is the default** so this does not fight for **port 80** (often already used by another reverse proxy on the same host). To use port 80 instead: `BIOBASE_LOCAL_PORT=80 docker compose up -d` (only if nothing else binds 80).

## 3. Make `biobase.local` resolve (otherwise the browser shows “Server not found”)

The gateway only answers HTTP; **your browser must resolve the hostname** to an IP. Pick one:

### A) mDNS (no hosts file) — server runs Avahi

On the **Docker host**, keep one of these running so LAN clients see **biobase.local**:

- Foreground: `./mdns/publish-biobase-local.sh`, or
- systemd: `mdns/biobase-mdns.service` (see comments in that file)

Optional: set `BIOBASE_LOCAL_IP` in the environment if the script’s IP guess is wrong. Some networks also need the client to support mDNS (Linux: `libnss-mdns` / `systemd-resolved`).

### B) Static `/etc/hosts` (works everywhere) — on the device running Firefox

Add one line to **`/etc/hosts`** (Linux/macOS) or `C:\Windows\System32\drivers\etc\hosts` (Windows), using the same machine’s IP you use to SSH to the host:

- **Browser on the same machine as Docker:** `127.0.0.1 biobase.local`
- **Another device on the LAN:** `<the host’s LAN IP>` `biobase.local` (e.g. `192.168.1.50 biobase.local`)

Then open: **`http://biobase.local:8880/`** (include the port if you use the default).

## 4. Nginx paths

- **`/`** — static index with links
- **`/bb/`** — Grafana
- **`/loki/`** — Loki
- **`/cs2/`** — CS2 control

Prometheus stays on host port **19090**; the home page links by hostname and port.

## 5. Grafana URL

Set in `bb_monitor_grafana` to match the URL you use in the browser, **including the port** if it is not 80:

```env
GF_SERVER_ROOT_URL=http://biobase.local:8880/bb/
```

(Use `http://biobase.local/bb/` only if you bound the gateway to port 80.) Restart Grafana after changing it.

## 6. What stays separate

- CS2 and RCON are unchanged; this layer only unifies **discovery and navigation** (per `../info.md`).
- Remote access from other networks is out of scope; use VPN or a tunnel.
