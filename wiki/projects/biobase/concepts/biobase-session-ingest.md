---
title: >-
  Biobase Session Ingest
category: concepts
tags: [cs2, game-analytics, postgres, loki, data-pipeline]
sources: [projects/biobase]
summary: >-
  Session-scoped ingest loop: RCON status polling to Postgres (ops) + Loki log
  lines to Postgres (ops), then parsed gameplay rows into game schema; cancel
  support; hub vs CLI start modes.
provenance:
  extracted: 0.80
  inferred: 0.15
  ambiguous: 0.05
created: 2026-04-28T00:00:00Z
updated: 2026-04-26T12:00:00Z
---

# Biobase Session Ingest

All data collection in Biobase is scoped to a **session** — a time window anchored to a **`public.biobase_cs2_match_session`** UUID. Every telemetry row has a `session_id` FK to that table.

Postgres stores **ops** vs **game** in separate schemas (see [[biobase-telemetry-schema]]). Grafana dashboards are split the same way (`ops.*` vs `game.*`).

## Gameplay data vs operations data

When analysing sessions, treat these groups separately:

| Kind | Postgres (qualified) | What it is |
|------|----------------------|------------|
| **Gameplay** | `game.biobase_cs2kz_*`, `game.biobase_cs2_game_event`, `game.biobase_cs2_movement_sample`, `game.biobase_cs2_round_stats` | CS2KZ local DB mirror and parsed **game** logs (kills, rounds, movement if emitted, KZ runs/jumpstats). |
| **Operations** | `ops.biobase_cs2_rcon_sample`, `ops.biobase_cs2_player_snapshot` | RCON **`status` polling** — server/map/bot counts and per-player snapshot lines from that command. Useful for ops, not KZ gameplay semantics. |
| **Raw / both** | `ops.biobase_cs2_log_line` | Raw Docker log text; may contain game events **or** ops noise — use parsers or keyword filters. Parsed rows land in **`game`**. |

Session lifecycle and RCON/Loki mechanics below apply to **how** rows are ingested; use the table above to decide **which** schema answers gameplay vs ops questions.

## Session Lifecycle

1. `POST /v1/sessions` (or `/v1/sessions/hub/start`) — creates a session row with `status=pending`, starts a background ingest loop.
2. Loop runs until `duration_seconds` elapsed or `cancel_requested=true`:
   - **RCON poll** every `rcon_interval_seconds` → **`ops.biobase_cs2_rcon_sample`** (+ **`ops.biobase_cs2_player_snapshot`**)
   - Optional **CS2KZ SQLite** poll → **`game.biobase_cs2kz_*`**
3. **Loki query** for the session wall-clock window → **`ops.biobase_cs2_log_line`** rows (bulk insert at end of loop in current code).
4. On stop, log lines are parsed by `log_parser.py` into **`game.biobase_cs2_game_event`**, **`game.biobase_cs2_movement_sample`**, **`game.biobase_cs2_round_stats`**.
5. Session `status` becomes `complete` (or `failed`).

Startup runs CS2 DDL/migration **before** ensuring the ingest stub table so legacy `public.biobase_ingest_sample` can move to **`ops`** first.

## Two Start Modes

| Mode | Endpoint | Behavior |
|------|----------|----------|
| **Hub** | `POST /v1/sessions/hub/start` | Long-lived, cancel via `hub/stop`. Used by the browser UI. |
| **CLI** | `POST /v1/sessions` with `duration_seconds` | Fixed-duration. `cancel_requested` can still interrupt. |

The hub stop path sets `cancel_requested=true` on the active hub session; the loop checks this flag each iteration.

## Server Prerequisites

Before starting a session on `bb_cs2_server`, run `short_match_rcon.sh` to:
- Unload CS2KZ (otherwise `bot_stop 1` freezes bots and game-mode hooks interfere)
- Enable game-event logging (`log on`, `sv_logecho 1`, `mp_logdetail 3`)

Without this, Loki has no log lines for the session window and **`game`** event tables are empty. Must repeat after every map change. See [[biobase-data-collection-prep]] for full details.

## Loki Integration

`bb_data_collection` queries Loki with a wall-clock window (stored as `loki_start_ns` / `loki_end_ns` on the session row). This avoids tailing files directly — Loki is the aggregator for all container logs including `bb_cs2_server`. The query returns lines for the session window in one shot at the end, not streaming.

## Summary API

`GET /v1/sessions/{id}/summary` returns a JSON (or text) summary; table names in the payload are **schema-qualified** (e.g. `ops.biobase_cs2_rcon_sample`, `game.biobase_cs2_game_event`). `GET /v1/sessions/{id}` returns the raw session row from **`public`**.

## Related

- [[biobase-telemetry-schema]] — `public` / `ops` / `game` tables and FKs
- [[biobase-log-parsing]] — how Loki log lines become structured **`game`** rows
- [[biobase]] — project overview
