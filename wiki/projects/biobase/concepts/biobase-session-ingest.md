---
title: >-
  Biobase Session Ingest
category: concepts
tags: [cs2, game-analytics, postgres, loki, data-pipeline]
sources: [projects/biobase]
summary: >-
  Session-scoped ingest loop: RCON status polling to Postgres + Loki log-line
  query to Postgres, with cancel support and two start modes (hub vs CLI).
provenance:
  extracted: 0.80
  inferred: 0.15
  ambiguous: 0.05
created: 2026-04-28T00:00:00Z
updated: 2026-04-28T07:00:00Z
---

# Biobase Session Ingest

All data collection in Biobase is scoped to a **session** — a time window anchored to a `biobase_cs2_match_session` UUID. Every telemetry row in every table has a `session_id` FK.

## Gameplay data vs operations data

When analysing sessions, treat these groups separately:

| Kind | Postgres tables | What it is |
|------|------------------|------------|
| **Gameplay** | `biobase_cs2kz_*` (player, run, jumpstat, sqlite cursor), `biobase_cs2_game_event`, `biobase_cs2_movement_sample`, `biobase_cs2_round_stats` | CS2KZ local DB mirror and parsed **game** logs (kills, rounds, movement if emitted, KZ runs/jumpstats). |
| **Operations** | `biobase_cs2_rcon_sample`, `biobase_cs2_player_snapshot` | RCON **`status` polling** — server/map/bot counts and snapshot lines from that command. Useful for ops, not KZ gameplay semantics. |
| **Raw / both** | `biobase_cs2_log_line` | Raw Docker log text; may contain game events **or** ops noise — use parsers or keyword filters. |

Session lifecycle and RCON/Loki mechanics below apply to **how** rows are ingested; use the table above to decide **which** tables answer gameplay questions.

## Session Lifecycle

1. `POST /v1/sessions` (or `/v1/sessions/hub/start`) — creates a session row with `status=pending`, starts a background ingest loop.
2. Loop runs until `duration_seconds` elapsed or `cancel_requested=true`:
   - **RCON poll** every `rcon_interval_seconds` → `biobase_cs2_rcon_sample` (+ player rows → `biobase_cs2_player_snapshot`)
   - **Loki query** for the session wall-clock window → `biobase_cs2_log_line` rows
3. On stop, log lines are parsed by `log_parser.py` into `biobase_cs2_game_event`, `biobase_cs2_movement_sample`, `biobase_cs2_round_stats`.
4. Session `status` becomes `complete` (or `error`).

## Two Start Modes

| Mode | Endpoint | Behavior |
|---|---|---|
| **Hub** | `POST /v1/sessions/hub/start` | Long-lived, cancel via `hub/stop`. Used by the browser UI. |
| **CLI** | `POST /v1/sessions` with `duration_seconds` | Fixed-duration. `cancel_requested` can still interrupt. |

The hub stop path sets `cancel_requested=true` on the active hub session; the loop checks this flag each iteration.

## Server Prerequisites

Before starting a session on `bb_cs2_server`, run `short_match_rcon.sh` to:
- Unload CS2KZ (otherwise `bot_stop 1` freezes bots and game-mode hooks interfere)
- Enable game-event logging (`log on`, `sv_logecho 1`, `mp_logdetail 3`)

Without this, Loki has no log lines for the session window and all event tables are empty. Must repeat after every map change. See [[biobase-data-collection-prep]] for full details.

## Loki Integration

`bb_data_collection` queries Loki with a wall-clock window (stored as `loki_start_ns` / `loki_end_ns` on the session row). This avoids tailing files directly — Loki is the aggregator for all container logs including `bb_cs2_server`. The query returns lines for the session window in one shot at the end, not streaming.

## Summary API

`GET /v1/sessions/{id}/summary` returns a text-mode summary of the session. `GET /v1/sessions/{id}` returns the raw session row.

## Related

- [[biobase-telemetry-schema]] — all tables FK'd to session
- [[biobase-log-parsing]] — how Loki log lines become structured events
- [[biobase]] — project overview
