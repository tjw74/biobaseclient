# bb_cs2_dashboard

CS2 admin UI (React + shadcn) behind **FastAPI** on port **8780**. Proxies to `bb_cs2_control` only (no RCON in this service).

## Run (with CS2 stack)

From `bb_cs2_server/`:

```bash
docker compose up -d bb_cs2_dashboard
```

After changing dashboard UI or `VITE_DASHBOARD_BASE`, rebuild the image so the static bundle updates: `docker compose build bb_cs2_dashboard && docker compose up -d bb_cs2_dashboard` (from `bb_cs2_server/`).

Open **`http://<host>:8780/admin/`** (trailing slash optional; `/admin` redirects to `/admin/`).

## Public URL (same host as the game)

The stack is set up so the UI and API live under **`/admin`** (see `BB_DASHBOARD_ROOT_PATH` and build arg `VITE_DASHBOARD_BASE` in `bb_cs2_server/docker-compose.yml`). Point **Caddy** (or another reverse proxy) at the dashboard container port **8780** and forward the **`/admin` prefix** without stripping it.

Example Caddy fragment (adjust the rest of the file for your game / DNS setup):

```caddyfile
cs2.clarionlab.dev {
	handle /admin* {
		reverse_proxy 127.0.0.1:8780
	}
}
```

Use **`https://cs2.clarionlab.dev/admin/`** in the browser. Set **`BB_DASHBOARD_COOKIE_SECURE=1`** on the dashboard when using HTTPS only.

To serve the dashboard at **site root** again (e.g. LAN): set build arg `VITE_DASHBOARD_BASE=/`, env `BB_DASHBOARD_ROOT_PATH=` empty, and rebuild — default compose targets **`/admin`** for sharing `cs2.clarionlab.dev` with game traffic.

## Auth

When **`BB_CS2_DASHBOARD_TOKEN`** is set (see compose default below), **everyone must sign in** before the SPA or `/api/*` (except `/health`) are usable — suitable for exposing the dashboard publicly behind HTTPS.

| Env | Role |
|-----|------|
| `BB_CS2_DASHBOARD_TOKEN` | **Shared password** for all operators. Also the value stored in the HttpOnly session cookie after a successful login. |
| `BB_CS2_DASHBOARD_USER` | Optional. If set, **username** on the login form must match exactly; if unset, any username is accepted and only the password is checked. |
| `BB_DASHBOARD_COOKIE_SECURE` | Set `1` / `true` when the site is served **only over HTTPS** (e.g. Caddy). Leave off on plain HTTP LAN tests or the browser will not keep the session cookie. |
| `BB_DASHBOARD_ROOT_PATH` | HTTP prefix for the app (default in compose: **`/admin`**). Must match the **`VITE_DASHBOARD_BASE`** used when building the frontend (e.g. `/admin/`). |

**Docker Compose default** (only used when you do not set `BB_CS2_DASHBOARD_TOKEN` in `.env`):

- **Password:** `biobase-cs2-dashboard-shared-key`  
- **Username:** any value (unless you set `BB_CS2_DASHBOARD_USER`)

Replace the default with a long random secret before real production exposure.

If `BB_CS2_DASHBOARD_TOKEN` is **unset** and you override the compose default to empty, the app skips the sign-in screen (dev / trusted LAN only).

`POST /api/auth/login` body: `{"username":"...", "password":"..."}` (legacy: `token` field is still accepted as an alias for `password`).

## Storage (clips uploads)

- **Proxmox (6TB):** `/srv/backups/...` (same export as ClarionCore’s `/mnt/backups/...`).
- **ClarionCore:** `BB_CLIPS_HOST_DIR` in `bb_cs2_server/.env` → Docker bind → container `/data/clips`.
- **NFS / exact path `.../biobase/clips`:** On many installs that directory is `root:root` `755` on the server, so **no ClarionCore user can write** until Proxmox is fixed (`scripts/proxmox-chown-biobase-clips.sh`). **Or** use a **bind mount**: writable `/mnt/backups/biobase_clips_upload` is mounted **on top of** `/mnt/backups/biobase/clips` (line in `/etc/fstab` + `apply-clips-bind.sh` does this automatically). Uploads then **do** appear under `ls /mnt/backups/biobase/clips`.
- **Apply / migrate / rebuild dashboard:** `./scripts/apply-clips-bind.sh` (sources `.env`; no sudo unless you need chown).

```bash
cd /home/clearmined/code/prod/biobase/bb_cs2_server
./scripts/apply-clips-bind.sh
```

## Other env (compose)

- `CS2_CONTROL_URL`, `CS2_CONTROL_TOKEN` — upstream control API + token (`X-Api-Key`) for bot and map-change routes.
- `BB_CLIPS_HOST_DIR` — host/VM path bound to `/data/clips` in compose (default `/mnt/backups/biobase/clips`).
- `BB_CLIPS_UPLOAD_DIR` — path inside the container (default `/data/clips`; must match the bind target). Legacy: `CLIPS_DIR`.
- `BB_CLIPS_VM_PATH` — optional mirror of `BB_CLIPS_HOST_DIR` passed into the container; upload JSON + toast use it so operators see the VM folder path. Usually leave unset in `.env` (compose sets it from `BB_CLIPS_HOST_DIR`).
- `BB_DASHBOARD_MAX_UPLOAD_MB` — upload cap (default 512).
- `BB_DEMO_PARSE_MAX_MB` — max size for demo parse upload/URL fetch (default **256**).
- `BB_DEMO_PARSE_ALLOW_URL_FETCH` — set `1` / `true` to allow `demo_url` on `POST /api/demo-parse-preview` (SSRF-hardened host allowlist).
- `BB_DEMO_PARSE_URL_HOSTS` — optional comma-separated hostname suffix allowlist (defaults include `figshare.com`, `github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`).

### Demo parse preview + fixture

- **API:** `POST /api/demo-parse-preview` (multipart: `file` **or** form `demo_url` if allowed; optional `event_scan_max`, default 80, max 200). Same auth as other `/api/*` routes.
- **Fixture (optional):** `make fetch-demo-fixture` in this directory writes `fixtures/sample.dem` when Figshare permits unattended download; otherwise see [`fixtures/README.md`](fixtures/README.md) for the canonical URL and manual download.
- **Test (optional):** with `fixtures/sample.dem` present, `python -m unittest tests.test_demo_parse_preview`.

## Rebuild after UI changes

```bash
docker compose build bb_cs2_dashboard && docker compose up -d bb_cs2_dashboard
```

Optional Grafana button: set `VITE_GRAFANA_URL` at **image build** time so the **Observability** page can link out (Docker `ARG`/`ENV` before `npm run build` in `Dockerfile`, or extend the compose build).
