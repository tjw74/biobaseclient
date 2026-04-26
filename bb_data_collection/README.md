# `bb_data_collection` — CS2 / KZ session ingest

Captures **game state** (via `bb_cs2_control` `/api/status` → JSON in Postgres) and **server log lines** (via Loki query of `bb_cs2_server` Docker logs) for a wall-clock window.

## Prereqs

- `bb_client` stack up (Postgres + this service on host port **28080** by default).
- `bb_monitor_loki` + Promtail (logs from `bb_cs2_server` are in Loki).
- `bb_cs2_control` must be on **`biobase_internal`** (same as this service). If `/api/status` from the container fails with DNS errors, recreate: `cd bb_cs2_server && docker compose up -d --force-recreate bb_cs2_control`.

## One command: 5-minute collection + summary

From the **biobase repo root**:

```bash
DURATION_SEC=300 DATA_URL=http://127.0.0.1:28080 ./run_kz_session.sh
```

Optional: `bb_cs2_server/short_match_rcon.sh` sets `mp_timelimit` / `mp_roundtime` (tune for your map/mode).

## API

- `POST /v1/sessions` — JSON `{ "duration_seconds": 300, "rcon_interval_seconds": 5, "label": "..." }` → starts background collection.
- `GET /v1/sessions/{uuid}` — status.
- `GET /v1/sessions/{uuid}/summary` — JSON; `Accept: text/plain` for a written report.

## Env (see `bb_client/docker-compose.yml`)

| Variable | Purpose |
|----------|---------|
| `LOKI_URL` | `http://bb_monitor_loki:3100` |
| `CS2_CONTROL_URL` | `http://bb_cs2_control:8765` |
| `CS2_CONTROL_TOKEN` | If `BB_CS2_CONTROL_TOKEN` is set on CS2 control |
| `BIOBASE_LOKI_LINE_LIMIT` | Max log lines per Loki query (default **5000**; Loki often caps here) |

## Tables

- `biobase_cs2_match_session` — one row per run.
- `biobase_cs2_rcon_sample` — time series of parsed RCON/status JSON.
- `biobase_cs2_log_line` — log text from Loki (plugins + engine; not a dedicated KZ protobuf API).

KZ-specific structured stats (jump times, etc.) are **not** in this repo unless the plugin prints them to **stdout** and they appear in these log lines.
