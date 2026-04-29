# Biobase — what exists, how it works, what’s next

This file is the **high-level map** of the repo: shipped behavior, data flows, operator entrypoints, and the **gap** between today’s ingest and full game telemetry (movement, shots, etc.).

---

## Operator entry: admin hub

- **URL:** `http://<docker-host-LAN-IP>:8880/` (default port; override with `BIOBASE_LOCAL_PORT` in `bb_biobase_local`).
- **What you get:** One dark-mode landing page with **Start / Stop bot game**, links to **Grafana** (`/bb/`), **Loki** (`/loki/`), and Prometheus (host port **19090** documented on the page), plus setup hints.
- **Reverse proxy:** `bb_biobase_local` nginx terminates HTTP and routes by path:
  - `/bb/` → Grafana
  - `/loki/` → Loki
  - `/cs2/` → `bb_cs2_control` (strip prefix; FastAPI on port 8765 inside the stack)
  - `/data/` → `bb_data_collection` (strip prefix; FastAPI on 8080)
  - `/` → static hub (`bb_biobase_local/html/index.html`)

Set **`GF_SERVER_ROOT_URL`** in `bb_monitor_grafana` to this hub’s origin plus `/bb/` so Grafana redirects and cookies work. Details: `bb_biobase_local/README.md`.

---

## What is already built

### CS2 control (`bb_cs2_server/control`)

- **Purpose:** Start/stop bot game via **RCON** (`mcrcon`), and expose **`GET /api/status`** (runs `status`, parses humans/bots/map/hostname from text).
- **Hub:** Bot buttons call **`POST /cs2/api/bots/start`** and **`/stop`** (with optional `X-Api-Key` if `BB_CS2_CONTROL_TOKEN` is set).
- **Important limitation:** `/api/status` does **not** include position, speed, KZ HUD metrics, or weapon fire — only what the vanilla `status` command returns.

### Data collection (`bb_data_collection` in `bb_client` compose)

- **Purpose:** For a **session** (time window), poll **`bb_cs2_control` `/api/status`** on an interval and append rows to Postgres; query **Loki** for **`bb_cs2_server`** log lines in the same wall-clock window and insert **one row per log line**.
- **HTTP API (via hub: `/data/...`):**
  - `POST /v1/sessions` — body: `duration_seconds`, `rcon_interval_seconds`, optional `label` → starts background ingest.
  - `GET /v1/sessions/{id}`, `GET /v1/sessions/{id}/summary`
  - **Hub automation:** `POST /v1/sessions/hub/start`, `POST /v1/sessions/hub/stop` — long-lived / cancel ingest aligned with the hub bot buttons (see hub `index.html`).
- **Postgres tables (public schema):**
  - **`biobase_cs2_match_session`** — one row per ingest run: id, label, status, timing, Loki window ns, error text, `cancel_requested` when stopping early.
  - **`biobase_cs2_rcon_sample`** — time series of **status poll** results: `sampled_at`, humans, bots, map, headline, `raw_json`, etc.
  - **`biobase_cs2_log_line`** — **timestamped text:** `ingested_at`, optional `loki_ts_ns`, **`line`** (anything that appeared in the server log stream ingested by Loki from the container).
  - **`biobase_ingest_sample`** — small **stub** table from early bootstrap (not game telemetry).
- **Env (see `bb_client/docker-compose.yml`):** `DATABASE_URL`, `LOKI_URL`, `CS2_CONTROL_URL`, `CS2_CONTROL_TOKEN`, `BIOBASE_LOKI_LINE_LIMIT`, etc.

### Observability

- **Loki + Promtail:** Container logs (including **`bb_cs2_server`**) → Loki; ingest reads them back for the session window.
- **Prometheus:** RCON exporter and related metrics (e.g. bot/human gauges) — see Grafana dashboards under folder **Biobase**.
- **Grafana provisioned dashboards** (`bb_monitor_grafana/provisioning/biobase-dashboards/`):
  - **Grafana — In-game player data** (`uid` `bb-data-ingestion`): game events, movement (`BIOBASE_POS_JSON`), player status snapshots, round stats — **tables ordered by game/reported time** (not session/ops catalog).
  - Others: **BioBase RCON**, **BioBase System**, **CS2 Server** (logs).

---

## How data flows (today)

1. **Hub** starts bots → **`bb_cs2_control`** drives RCON.
2. **Hub** (same action) calls **`/data/v1/sessions/hub/start`** so **`bb_data_collection`** opens a session and loops: **HTTP status** → Postgres; **Loki query** → **`biobase_cs2_log_line`**.
3. **Stop** requests cancel on hub sessions; ingest finishes the loop, flushes Loki range, marks session complete.
4. **Grafana** reads Postgres (and Prometheus/Loki) for spot checks.

**KZ / plugin “HUD” numbers** (speed, strafe, jump distance, coordinates) are **not** in `biobase_cs2_rcon_sample` unless you put them there via a new source. They **may** appear partially or rarely in **`biobase_cs2_log_line.line`** only if the server/plugins **print** those values to stdout/stderr in a form that reaches Docker logs.

---

## CLI tools: `tools/run_kz_session.sh` and `tools/run_ingest_session.sh`

Both live under **`tools/`** (run them from the repo root with `./tools/...`).

| Script | Role |
|--------|------|
| **`tools/run_kz_session.sh`** | **Full story:** optionally runs `bb_cs2_server/short_match_rcon.sh`; **`POST`s** `DATA_URL/v1/sessions` with `duration_seconds`, `rcon_interval_seconds: 5`, `label` default `kz-data-${DURATION_SEC}s`; **`POST`s** `CS2_URL/api/bots/start`; **sleeps** `DURATION_SEC`; **polls** until session `complete`; prints **text summary** and reminds you of **JSON summary** URL. |
| **`tools/run_ingest_session.sh`** | **Same executable behavior** as `run_kz_session.sh` — only the name differs (for “ingest” wording in docs/Grafana). |

**Defaults:** `DATA_URL=http://127.0.0.1:28080`, `CS2_URL=http://127.0.0.1:8765`, `DURATION_SEC=300`. Override as needed. Use **`BB_CS2_CONTROL_TOKEN`** if the control API is protected.

**Difference vs hub:** The hub uses **hub** start/stop (long-lived / cancel). These scripts use **`POST /v1/sessions`** with a **fixed duration** — useful for reproducible runs and CI-style smokes without the browser.

---

## What must be implemented for granular data (“all of it”)

Today we only reliably have: **coarse RCON status time series** + **raw server log lines** + **Prometheus** where exporters exist. To get **movement, shots, and similarly granular** data into Postgres (and Grafana), you need **explicit capture paths** from the game or plugins into something Biobase already ingests or a **new** ingest API/table family.

### 1. Movement / KZ-style metrics (positions, velocity, strafe, jump stats, distances)

- **Problem:** HUD draws client/server-side values that are **not** in `status` or in logs unless something **emits** them.
- **Directions (pick one or combine):**
  - **Server plugin or companion** periodically **prints structured lines** to console (e.g. prefix `BIOBASE_KZ_JSON ...`) → already flows to **`biobase_cs2_log_line`** → optional **parser job** loads **`biobase_cs2_kz_sample`** (or similar) with typed columns.
  - **HTTP endpoint** on the host or sidecar (plugin posts JSON) → **`bb_data_collection`** new route or worker polls and **INSERT**s wide rows keyed by `session_id` + `ts`.
  - **Demo / replay parsing** offline or streaming — separate pipeline into Postgres tables keyed by match/session.
  - **Game events / official APIs** (if/when exposed for dedicated server) — subscribe and map to tables.

The more **granular** the desired rate, the more you must watch **volume**, **DB indexing**, and **backpressure**.

### 2. Shots fired, hits, damage, weapon use

- Same pattern: **game events**, **plugin hooks**, or **logging** that actually records each shot — then either:
  - landed in **logs** → parse `line`, or
  - landed via a **new structured ingest** → **`biobase_cs2_combat_event`** (example name) with columns: `session_id`, `game_time` or wall `ts`, shooter slot/steamid if available, weapon, hit group, damage, etc.

RCON **`status`** will **not** provide per-shot data.

### 3. “Everything we can get”

- **Inventory sources:** RCON commands beyond `status`, plugin CLIs, Metamod APIs, third-party stats services, file drops on disk, metrics already in **Prometheus** (scrape → remote write or periodic copy to Postgres if you need SQL joins).
- **Schema:** New **`biobase_*`** tables per domain (movement, combat, economy, round events) with **`session_id`** FK, monotonic keys, and **`timestamptz`** (or server tick) for time series.
- **`bb_data_collection`:** New loops or consumers: poll URLs, tail files, subscribe to NATS/Kafka, parse log regex, etc.; respect **`cancel_requested`** and session boundaries like the existing ingest loop.
- **Privacy / size:** High-frequency player data grows fast — retention, PII (Steam IDs), and sampling policy should be explicit.

---

## Checklist for anyone touching the deployment

- Know **LAN IP** or use `127.0.0.1` on the Docker host.
- Hub: **`http://<IP>:8880/`**; Grafana: **`/bb/`** with **`GF_SERVER_ROOT_URL`** set.
- Stacks: **`bb_client`** (Postgres + `bb_data_collection`), **`bb_cs2_server`**, **`bb_monitor_loki`**, **`bb_biobase_local`**, **`bb_monitor_grafana`**, **`bb_monitor_prometheus`**, shared **`biobase_internal`** (and friends per compose).

---

## Remote access

Access from outside the LAN is **not** covered here; use VPN or a tunnel and still terminate TLS at something you control.
