---
title: >-
  Biobase Telemetry Schema
category: concepts
tags: [cs2, postgres, game-analytics, schema]
sources: [projects/biobase]
summary: >-
  Six Postgres tables capturing CS2 telemetry: session, RCON samples, log
  lines, player snapshots, game events, movement samples, and round stats.
provenance:
  extracted: 0.90
  inferred: 0.08
  ambiguous: 0.02
created: 2026-04-28T00:00:00Z
updated: 2026-04-28T00:00:00Z
---

# Biobase Telemetry Schema

All tables live in the `public` schema with `biobase_cs2_` prefix. Every telemetry table has a `session_id uuid` FK → `biobase_cs2_match_session`. Schema is idempotent (`IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`) so migrations don't fail on re-run.

## Tables

### `biobase_cs2_match_session`
One row per ingest run. Anchor for all telemetry.

| Column | Notes |
|---|---|
| `id` | UUID PK |
| `label` | Human-readable run label |
| `status` | `pending` → `running` → `complete` / `error` |
| `duration_requested` | Target seconds |
| `loki_start_ns / loki_end_ns` | Wall-clock window for Loki queries |
| `cancel_requested` | Bool; hub stop sets this to interrupt the loop |
| `error_message` | Set on failure |

### `biobase_cs2_rcon_sample`
Time series from RCON `status` polls — coarse server-wide data only.

| Column | Notes |
|---|---|
| `sampled_at` | Poll timestamp |
| `humans / bots / map / hostname` | Parsed from `status` output |
| `rcon_ok` | Whether RCON was reachable |
| `raw_json` | Full parsed status as JSONB |

Index: `(session_id, sampled_at)`.

### `biobase_cs2_log_line`
Raw CS2 server log lines as ingested from Loki. Keyed by `(session_id)`.

### `biobase_cs2_player_snapshot`
Per-player rows captured on each RCON poll (linked to `rcon_sample_id`). Captures: `userid`, `player_name`, `steamid`, `ping`, `loss`, `state`, `connected`.

Indexes: `(session_id, sampled_at)`, `(player_name, steamid)`.

### `biobase_cs2_game_event`
Structured events parsed from log lines by `log_parser.py`. Linked to `log_line_id` where the source line is known.

| Column | Notes |
|---|---|
| `event_type` | `kill`, `round_start`, `round_end`, `connect`, `biobase_pos`, etc. |
| `attacker_*` / `victim_*` | Player entity fields (name, steamid, team) |
| `weapon / headshot` | Kill events only |
| `extra_json` | Event-specific fields as JSONB |
| `raw_line` | Original log line (always populated) |

Indexes: `(session_id, event_type)`, `(session_id, event_ts)`.

### `biobase_cs2_movement_sample`
Plugin-emitted position/velocity data — only populated when a CS2 plugin prints `BIOBASE_POS_JSON` lines. High-frequency, watch volume.

Captures: `tick`, `player_name`, `steamid`, `pos_x/y/z`, `vel_x/y/z`, `speed`, `yaw`, `pitch`, `on_ground`.

Indexes: `(session_id, sampled_at)`, `(player_name, steamid)`.

### `biobase_cs2_round_stats`
Per-player cumulative stats at end of each round. Parsed from `JSON_BEGIN...JSON_END` blocks CS2 emits in logs. ~30 numeric combat fields per player per round (kills, deaths, dmg, hsp, kdr, adr, mvp, etc.).

Index: `(session_id, round_number)`.

## What RCON Cannot Provide

Positions, per-shot data, movement metrics — none come from `status` RCON. These require CS2 server plugins using the [[biobase-log-parsing|BIOBASE plugin protocol]]. ^[inferred]

## Related

- [[biobase-session-ingest]] — lifecycle that writes to all tables
- [[biobase-log-parsing]] — parser that populates game_event, movement_sample, round_stats
- [[biobase]] — project overview
