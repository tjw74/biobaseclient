---
title: >-
  Biobase
category: projects
tags: [cs2, game-analytics, postgres, grafana, docker, electron, desktop-client]
sources: [projects/biobase]
summary: >-
  CS2 performance analytics platform: desktop Electron client (primary UI),
  phone companion via QR, admin dashboard, auto-update pipeline, and CS2
  server data pipeline. Design philosophy: extreme friction reduction and
  zero-inference labeling.
provenance:
  extracted: 0.85
  inferred: 0.12
  ambiguous: 0.03
created: 2026-04-28T00:00:00Z
updated: 2026-06-04T15:54:47Z
---

# Biobase

A self-hosted analytics platform for Counter-Strike 2 dedicated servers. It captures telemetry during a **session** into Postgres: **`public`** holds the session row; **`ops`** holds RCON samples, raw Loki lines, and status snapshots; **`game`** holds parsed events, movement, round stats, and the CS2KZ SQLite mirror. Grafana uses separate dashboards for **ops** vs **game** queries.

The user-facing product direction is now **Windows desktop client first**: a local Biobase client runs beside Steam/CS2, detects or saves `.dem` files, parses demo timelines locally, displays movement statistics and an overlay HUD, captures bio/EMG sensor input later, and uploads structured data to the central Biobase server. The existing web/admin surfaces remain operator tools rather than the primary replay/HUD experience. See [[biobase-windows-client-primary-ui]].

MATCH / game-plane ingest (outside the Postgres session recorder) MAY emit versioned **`biobase-telemetry-v1`** JSON bundles documented under `docs/cs2/` plus the `tools/biobase_demo_reconcile.py` smoke checks before HTTP drop targets land (see [[biobase-cs2-telemetry-and-reconciliation]]).

## Architecture

```
Hub (port 8880)
  └── nginx reverse proxy (bb_biobase_local)
        ├── /bb/     → Grafana
        ├── /loki/   → Loki
        ├── /cs2/    → bb_cs2_control (FastAPI :8765)
        └── /data/   → bb_data_collection (FastAPI :8080)

CS2 Server (bb_cs2_server)
  └── logs → Docker stdout → Loki → bb_data_collection queries Loki by session window

bb_cs2_control
  └── RCON (mcrcon) → CS2 server → bb_data_collection polls status

bb_cs2_dashboard (bb_cs2_server compose)
  └── FastAPI :8780 + Vite SPA under /admin → clips → VM path via BB_CLIPS_HOST_DIR (see [[biobase-cs2-admin-dashboard]])
```

## Design Philosophy

- [[zero-inference-labeling]] — Every label communicates with zero cognitive inference from the user. If the name makes you ask "what's that?", it has failed.
- **Extreme friction reduction** — Every interaction that can be eliminated, is eliminated. No unnecessary inputs, no learning curves, controls live where users are already looking.

## Key Concepts

- [[biobase-product-roadmap]] — Phased delivery plan, progress tracking, current state (v0.1.44)
- [[biobase-windows-client-primary-ui]] — Desktop client architecture, three UI surfaces, design decisions
- [[llm-wiki-pattern]] — Karpathy **LLM Wiki** for this monorepo (`wiki/` vault; skills in `obsidian-wiki/`; raw gist copy under `docs/llm-wiki-raw/`)
- [[biobase-session-ingest]] — session lifecycle, RCON polling, Loki query
- [[biobase-telemetry-schema]] — `public` / `ops` / `game` schemas, tables, Grafana split
- [[biobase-log-parsing]] — CS2 log format, BIOBASE plugin protocol, event types
- [[biobase-hub-routing]] — nginx path routing, hub UI, GF_SERVER_ROOT_URL requirement
- [[biobase-data-collection-prep]] — CS2 server prep for bot-deathmatch sessions (CS2KZ, logging cvars)
- [[biobase-cs2-admin-dashboard]] — CS2 **admin** UI (`/admin`), map/bots/status, **clips uploads**, NFS/bind on ClarionCore
- [[biobase-cs2-telemetry-and-reconciliation]] — Telemetry flush bundle schema v1, ZSTD `{match_id}.jsonl.zst` drop MVP, reconcile stub + parser linkage

## Stacks and Services

| Compose stack | Role |
|---|---|
| `bb_client` | Postgres + `bb_data_collection` |
| `bb_cs2_server` | CS2 dedicated server + **bb_cs2_control** + **bb_cs2_dashboard** (admin UI :8780, `/admin`) |
| `bb_monitor_loki` | Loki + Promtail (collects container logs) |
| `bb_monitor_grafana` | Grafana (provisioned dashboards; game dashboard sets `GF_PANELS_DISABLE_SANITIZE_HTML` for blue table headers in Overview HTML) |
| `bb_monitor_prometheus` | Prometheus + RCON exporter |
| `bb_biobase_local` | nginx hub, operator entry point |

All stacks share `biobase_internal` Docker network (and friends per compose).

## CLI Tools

Postgres shell (`bb_client/docker-compose.yml` uses container **`bb_postgres`**; substitute your local name if different, e.g. **`dc_postgres`**, when running `docker exec`): `docker exec -it bb_postgres psql -U biobase -d biobase`. Inside `psql`, `\dt` only shows `public`; use `\dt *.*` / `\dn` to see `ops` / `game`. Movement samples: `game.biobase_cs2_movement_sample`. See [[biobase-telemetry-schema#Inspecting Postgres (CLI)|telemetry schema → CLI]] for copy-paste queries and empty-`game` checks.

`tools/run_kz_session.sh` and `tools/run_ingest_session.sh` — start a fixed-duration ingest session from the CLI without the browser. Useful for reproducible runs. Defaults: `DATA_URL=http://127.0.0.1:28080`, `CS2_URL=http://127.0.0.1:8765`, `DURATION_SEC=300`.

`bb_cs2_server/short_match_rcon.sh` — prepares `bb_cs2_server` for bot-deathmatch data collection: unloads CS2KZ plugin, switches game mode to casual, unfreezes bots, and enables game-event logging. Must be re-run after every map change. See [[biobase-data-collection-prep]].

## Key Constraint: RCON Gives Coarse Data

`GET /api/status` only returns what the vanilla `status` RCON command returns — human/bot count, map, hostname. It does **not** return positions, velocities, or per-shot data. Granular telemetry requires CS2 server plugins that emit structured `BIOBASE_POS_JSON` / `BIOBASE_EVENT_JSON` log lines. ^[inferred]
