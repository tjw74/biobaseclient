---
title: >-
  Biobase Telemetry Schema
category: concepts
tags: [cs2, postgres, game-analytics, schema]
sources: [projects/biobase]
summary: >-
  Postgres layout: public session anchor; ops (RCON, raw logs, status snapshots);
  game (parsed events, movement, round stats, CS2KZ mirror). Cross-schema FKs from game to ops.
provenance:
  extracted: 0.90
  inferred: 0.08
  ambiguous: 0.02
created: 2026-04-28T00:00:00Z
updated: 2026-04-26T12:00:00Z
---

# Biobase Telemetry Schema

Telemetry is split across **three PostgreSQL schemas**:

| Schema | Role |
|--------|------|
| **`public`** | Session anchor only: `biobase_cs2_match_session`. All other tables use `session_id` → this row. |
| **`ops`** | **Operations ingest**: RCON/status samples, raw Loki log lines, per-poll player snapshots from `status`, and the `biobase_ingest_sample` stub table. |
| **`game`** | **Gameplay**: parsed log output (`game_event`, `movement_sample`, `round_stats`) and the **CS2KZ SQLite mirror** (`biobase_cs2kz_*`). |

Cross-schema foreign keys:

- `game.biobase_cs2_game_event.log_line_id` → `ops.biobase_cs2_log_line(id)` (nullable)
- `game.biobase_cs2_movement_sample.log_line_id` → `ops.biobase_cs2_log_line(id)` (nullable)
- All `session_id` columns still reference **`public.biobase_cs2_match_session`**.

DDL is idempotent (`CREATE SCHEMA IF NOT EXISTS`, `IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`). **`bb_data_collection`** runs the same statements on startup. Legacy volumes that still have tables in `public` are migrated automatically (move to `ops` / `game` before creating new empty tables); `bb_client/initdb/007_ops_game_schema_migration.sql` mirrors that for fresh init ordering.

## Tables (by schema)

### `public.biobase_cs2_match_session`

One row per ingest run. Anchor for all telemetry.

| Column | Notes |
|--------|------|
| `id` | UUID PK |
| `label` | Human-readable run label |
| `status` | `pending` → `running` → `complete` / `failed` |
| `duration_requested` | Target seconds |
| `loki_start_ns` / `loki_end_ns` | Wall-clock window for Loki queries |
| `cancel_requested` | Bool; hub stop sets this to interrupt the loop |
| `error_message` | Set on failure or Loki/truncate notes |

### `ops.biobase_ingest_sample`

Small stub table (historical first-boot check). Not used for gameplay.

### `ops.biobase_cs2_rcon_sample`

Time series from RCON `status` polls — coarse server-wide data.

| Column | Notes |
|--------|------|
| `sampled_at` | Poll timestamp |
| `humans` / `bots` / `map` / `hostname` | Parsed from `status` output |
| `rcon_ok` | Whether RCON was reachable |
| `raw_json` | Full parsed status as JSONB |

Index: `(session_id, sampled_at)`.

### `ops.biobase_cs2_log_line`

Raw CS2 server log lines from Loki for the session window.

### `ops.biobase_cs2_player_snapshot`

Per-player rows on each RCON poll (`rcon_sample_id` → `ops.biobase_cs2_rcon_sample`). Fields: `userid`, `player_name`, `steamid`, `ping`, `loss`, `state`, `connected`.

Indexes: `(session_id, sampled_at)`, `(player_name, steamid)`.

### `game.biobase_cs2_game_event`

Structured events from `log_parser.py`. `log_line_id` links to the ops raw line when known.

| Column | Notes |
|--------|------|
| `event_type` | `kill`, `round_start`, `round_end`, `connect`, `biobase_pos`, etc. |
| `attacker_*` / `victim_*` | Player entity fields |
| `weapon` / `headshot` | Kill events |
| `extra_json` | Event-specific JSONB |
| `raw_line` | Original log line (always populated) |

Indexes: `(session_id, event_type)`, `(session_id, event_ts)`.

### `game.biobase_cs2_movement_sample`

Plugin `BIOBASE_POS_JSON` data. High-frequency; watch volume.

### `game.biobase_cs2_round_stats`

Per-player cumulative stats from `JSON_BEGIN...JSON_END` round blocks in logs.

Index: `(session_id, round_number)`.

### `game.biobase_cs2kz_*` (CS2KZ SQLite mirror)

| Table | Role |
|-------|------|
| `biobase_cs2kz_sqlite_cursor` | Incremental `rowid` cursor per session / source SQLite table |
| `biobase_cs2kz_player` | Players from KZ SQLite |
| `biobase_cs2kz_run` | Times (runs) |
| `biobase_cs2kz_jumpstat` | Jumpstats |

## Grafana

Provisioned dashboards query **qualified** names:

- **Game data (parsed + CS2KZ)** — `game.*` panels (uid `bb-data-ingestion`).
- **Ops ingest (RCON & logs)** — `ops.*` panels (uid `bb-ops-ingest`).

## What RCON Cannot Provide

Positions, per-shot data, movement metrics — none come from `status` RCON. These require CS2 server plugins using the [[biobase-log-parsing|BIOBASE plugin protocol]]. ^[inferred]

## Related

- [[biobase-session-ingest]] — lifecycle that writes to these tables
- [[biobase-log-parsing]] — parser that populates `game` tables from `ops` log lines
- [[biobase]] — project overview
