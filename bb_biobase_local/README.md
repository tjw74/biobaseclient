# Biobase LAN admin hub (nginx gateway)

Single browser entry on the **host’s address** and port, e.g. **`http://<LAN-IP>:8880/`** or **`http://127.0.0.1:8880/`** on the machine running Docker (default port **8880**).

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

## 3. How to open it

- **Same machine as Docker:** `http://127.0.0.1:8880/` (or `localhost:8880`).
- **Another device on the LAN:** `http://<Docker-host-LAN-IP>:8880/` (e.g. `http://192.168.1.113:8880/`). You can bookmark that URL; optional static names are **router DNS** or **`/etc/hosts`** on the client if you assign a hostname yourself — Biobase does not rely on a reserved `.local` mDNS name for the app.

## 4. Nginx paths

- **`/`** — hub with links **and embedded bot game controls** (uses `/cs2/api/…` under the hood)
- **`/bb/`** — Grafana
- **`/loki/`** — Loki
- **`/cs2/`** — standalone CS2 control UI (same FastAPI as the hub controls)

Prometheus stays on host port **19090**; the home page links by hostname and port.

## 5. Grafana URL

Set in `bb_monitor_grafana` to match the **exact origin** you use in the browser (scheme + host + port + `/bb/`):

```env
GF_SERVER_ROOT_URL=http://192.168.1.113:8880/bb/
```

(Replace the IP with your host’s LAN address, or use `127.0.0.1` when you only use Grafana from the same machine.) Restart Grafana after changing it.

## 6. Troubleshooting

1. **Use the hub port in the URL.** The gateway defaults to **`:8880`**. A URL with **no** port often hits **port 80**, which may be a **different** app. Open **`http://<host>:8880/`** (or your `BIOBASE_LOCAL_PORT`).

2. **Grafana is not on `/`.** Open **`/bb/`** from this hub, sign in, then choose a dashboard from the menu.

3. **`GF_SERVER_ROOT_URL` mismatches the browser.** If Grafana redirects wrongly, set it to the same origin you type in the address bar, plus `/bb/`.

4. **Cannot reach from another PC** — use the server’s **LAN IP**, check firewall (allow TCP **8880** from the LAN), and confirm `docker compose` for this directory is up.

## 7. What stays separate

- CS2 and RCON are unchanged; this layer only unifies **navigation** under one HTTP origin (per `../info.md`).
- Remote access from other networks is out of scope; use VPN or a tunnel.
