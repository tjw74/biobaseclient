---
title: >-
  Biobase
category: projects
tags: [cs2, game-analytics, postgres, grafana, docker]
sources: [projects/biobase]
summary: >-
  CS2 game analytics platform: collects server telemetry into Postgres
  (public session + ops ingest + game parsed/KZ data) and exposes it through
  Grafana dashboards.
provenance:
  extracted: 0.85
  inferred: 0.12
  ambiguous: 0.03
created: 2026-04-28T00:00:00Z
updated: 2026-04-26T20:00:00Z
---

# Biobase

A self-hosted analytics platform for Counter-Strike 2 dedicated servers. It captures telemetry during a **session** into Postgres: **`public`** holds the session row; **`ops`** holds RCON samples, raw Loki lines, and status snapshots; **`game`** holds parsed events, movement, round stats, and the CS2KZ SQLite mirror. Grafana uses separate dashboards for **ops** vs **game** queries.

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
```

## Key Concepts

- [[biobase-session-ingest]] — session lifecycle, RCON polling, Loki query
- [[biobase-telemetry-schema]] — `public` / `ops` / `game` schemas, tables, Grafana split
- [[biobase-log-parsing]] — CS2 log format, BIOBASE plugin protocol, event types
- [[biobase-hub-routing]] — nginx path routing, hub UI, GF_SERVER_ROOT_URL requirement
- [[biobase-data-collection-prep]] — CS2 server prep for bot-deathmatch sessions (CS2KZ, logging cvars)

## Stacks and Services

| Compose stack | Role |
|---|---|
| `bb_client` | Postgres + `bb_data_collection` |
| `bb_cs2_server` | CS2 dedicated server |
| `bb_monitor_loki` | Loki + Promtail (collects container logs) |
| `bb_monitor_grafana` | Grafana (provisioned dashboards; game dashboard sets `GF_PANELS_DISABLE_SANITIZE_HTML` for blue table headers in Overview HTML) |
| `bb_monitor_prometheus` | Prometheus + RCON exporter |
| `bb_biobase_local` | nginx hub, operator entry point |

All stacks share `biobase_internal` Docker network (and friends per compose).

## CLI Tools

`tools/run_kz_session.sh` and `tools/run_ingest_session.sh` — start a fixed-duration ingest session from the CLI without the browser. Useful for reproducible runs. Defaults: `DATA_URL=http://127.0.0.1:28080`, `CS2_URL=http://127.0.0.1:8765`, `DURATION_SEC=300`.

`bb_cs2_server/short_match_rcon.sh` — prepares `bb_cs2_server` for bot-deathmatch data collection: unloads CS2KZ plugin, switches game mode to casual, unfreezes bots, and enables game-event logging. Must be re-run after every map change. See [[biobase-data-collection-prep]].

## Key Constraint: RCON Gives Coarse Data

`GET /api/status` only returns what the vanilla `status` RCON command returns — human/bot count, map, hostname. It does **not** return positions, velocities, or per-shot data. Granular telemetry requires CS2 server plugins that emit structured `BIOBASE_POS_JSON` / `BIOBASE_EVENT_JSON` log lines. ^[inferred]
