# bb_cs2_dashboard

CS2 admin UI (React + shadcn) behind **FastAPI** on port **8780**. Proxies to `bb_cs2_control` only (no RCON in this service).

## Run (with CS2 stack)

From `bb_cs2_server/`:

```bash
docker compose up -d bb_cs2_dashboard
```

Open `http://<host>:8780/`.

## Auth

When **`BB_CS2_DASHBOARD_TOKEN`** is set (see compose default below), **everyone must sign in** before the SPA or `/api/*` (except `/health`) are usable — suitable for exposing the dashboard publicly behind HTTPS.

| Env | Role |
|-----|------|
| `BB_CS2_DASHBOARD_TOKEN` | **Shared password** for all operators. Also the value stored in the HttpOnly session cookie after a successful login. |
| `BB_CS2_DASHBOARD_USER` | Optional. If set, **username** on the login form must match exactly; if unset, any username is accepted and only the password is checked. |
| `BB_DASHBOARD_COOKIE_SECURE` | Set `1` / `true` when the site is served **only over HTTPS** (e.g. Caddy). Leave off on plain HTTP LAN tests or the browser will not keep the session cookie. |

**Docker Compose default** (only used when you do not set `BB_CS2_DASHBOARD_TOKEN` in `.env`):

- **Password:** `biobase-cs2-dashboard-shared-key`  
- **Username:** any value (unless you set `BB_CS2_DASHBOARD_USER`)

Replace the default with a long random secret before real production exposure.

If `BB_CS2_DASHBOARD_TOKEN` is **unset** and you override the compose default to empty, the app skips the sign-in screen (dev / trusted LAN only).

`POST /api/auth/login` body: `{"username":"...", "password":"..."}` (legacy: `token` field is still accepted as an alias for `password`).

## Other env (compose)

- `CS2_CONTROL_URL`, `CS2_CONTROL_TOKEN` — upstream control API + token (`X-Api-Key`) for bot and map-change routes.
- `CLIPS_DIR` — upload target (default `/data/clips`); bind a host path in compose for production.
- `BB_DASHBOARD_MAX_UPLOAD_MB` — upload cap (default 512).

## Rebuild after UI changes

```bash
docker compose build bb_cs2_dashboard && docker compose up -d bb_cs2_dashboard
```

Optional Grafana button: set `VITE_GRAFANA_URL` at **image build** time so the **Observability** page can link out (Docker `ARG`/`ENV` before `npm run build` in `Dockerfile`, or extend the compose build).
