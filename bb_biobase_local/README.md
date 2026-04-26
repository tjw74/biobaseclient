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

### A) mDNS (recommended) — add only `biobase.local` via Avahi

On the **Docker host** (does **not** change `avahi-daemon.conf` or other mDNS data except one new `services` file):

```bash
cd bb_biobase_local/mdns
sudo BIOBASE_LOCAL_PORT=8880 ./install-biobase-mdns.sh
```

This installs a small systemd unit that runs `avahi-publish` for **`biobase.local`** and an optional `/_http._tcp` advertisement for the same port. Details: `mdns/README.md`.

- Foreground (no install): `mdns/publish-biobase-local.sh` (Ctrl+C to stop)  
- Optional: `/etc/default/biobase-mdns` for `BIOBASE_LOCAL_IP` / `BIOBASE_MDNS_NAME`  
- Clients on the LAN need mDNS support (e.g. macOS; Linux often `avahi` / `libnss-mdns` / `systemd-resolved`).

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

## 6. Troubleshooting: “no dashboard” or wrong page

1. **Use the hub port in the URL.** The Biobase gateway defaults to **`:8880`**. A bare `http://biobase.local` (port **80**) is often a **different** nginx or app on the same host. Open **`http://biobase.local:8880/`** (or your `BIOBASE_LOCAL_PORT`).

2. **Grafana is not on `/`.** After the hub page loads, open **Grafana** (path **`/bb/`**). You get a sign-in or Grafana home — then use the **menu to open a dashboard** (e.g. under “Biobase” or “Dashboards”). There is no single auto-opened “default” view until you pick one.

3. **`GF_SERVER_ROOT_URL` mismatches the browser.** If Grafana redirects to the wrong host or shows an empty/redirect loop, set `GF_SERVER_ROOT_URL=http://biobase.local:8880/bb/` in `bb_monitor_grafana` and restart Grafana.

4. **Name does not resolve** — add `biobase.local` to `/etc/hosts` or run mDNS (see §3).

### “Server not found” for `http://biobase.local:8880` (e.g. Firefox)

That error is almost always **name resolution** on the **machine running the browser**, not a missing Grafana page.

1. **You are on another PC / phone** — `biobase.local` is not a public DNS name. Add a static line on **that** device: the Docker host’s LAN address and `biobase.local` (e.g. `192.168.1.113 biobase.local`). On the host, run `./print-client-hint.sh` to print a ready-to-paste line for your current IP.

2. **You are on the same machine as Docker** — use:  
   `127.0.0.1   biobase.local` in `/etc/hosts` on that machine, then `http://biobase.local:8880/`.

3. **Port reaches nothing** — on the host, `ss -tlnp | grep 8880` should show the gateway; open the host firewall for TCP 8880 from the client’s network if needed.

4. **Firefox still ignores `.local`** — in `about:config`, set `network.dns.localDomains` to `biobase.local` (after fixed hosts or mDNS is working).

## 7. What stays separate

- CS2 and RCON are unchanged; this layer only unifies **discovery and navigation** (per `../info.md`).
- Remote access from other networks is out of scope; use VPN or a tunnel.
