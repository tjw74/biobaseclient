---
title: >-
  Biobase Log Parsing and Plugin Protocol
category: concepts
tags: [cs2, game-analytics, log-parsing, plugin-protocol]
sources: [projects/biobase]
summary: >-
  CS2 server logs parsed via regex into structured events. Plugin protocol uses
  BIOBASE_POS_JSON / BIOBASE_EVENT_JSON log lines as a bridge to Postgres.
provenance:
  extracted: 0.85
  inferred: 0.10
  ambiguous: 0.05
created: 2026-04-28T00:00:00Z
updated: 2026-04-28T00:00:00Z
---

# Biobase Log Parsing and Plugin Protocol

`bb_data_collection/app/log_parser.py` parses raw CS2 server log lines into structured dicts that map directly to Postgres tables.

## CS2 Log Format

CS2 uses the HL/Source Engine log prefix on most lines:
```
L MM/DD/YYYY - HH:MM:SS: <payload>
```
Some entity-event lines (e.g., `OnPreResetRound`, `ChangeTeam`) lack this prefix — the parser handles both with and without it.

Player entities appear as: `"Name<slot><steamid><team>"`

## Supported Event Types (`biobase_cs2_game_event.event_type`)

| Type | Source pattern |
|---|---|
| `kill` | `"att" killed "vic" with "weapon" [(headshot)]` |
| `round_start / round_end` | `World triggered "Round_Start"` |
| `game_over / game_commencing` | `World triggered "Game_Over"` |
| `world_<x>` | Any other `World triggered` event |
| `team_score` | `Team "X" scored "N" with "M" players` |
| `connect / disconnect` | Player connected/disconnected with optional reason |
| `say / say_team` | Player chat messages |
| `freeze_period` | `Starting Freeze period` |
| `match_status` | `MatchStatus: Score: X:Y on map "MAP" RoundsPlayed: N` |
| `player_reset` | `OnPreResetRound` entity event |
| `team_change` | `ChangeTeam()` entity event |
| `biobase_pos` | Plugin-emitted position line (also → movement_sample) |
| `biobase_event` | Plugin-emitted arbitrary event |

## BIOBASE Plugin Protocol

CS2 server plugins can emit structured data by printing to console (which flows to Docker stdout → Loki → `biobase_cs2_log_line`). The parser recognizes two prefixes:

```
BIOBASE_POS_JSON  {"player":"Name","steamid":"BOT","tick":N,"pos":[x,y,z],"vel":[vx,vy,vz],"speed":s,"yaw":y,"pitch":p,"on_ground":bool}
BIOBASE_EVENT_JSON {"type":"jump","player":"Name","steamid":"...", ...}
```

`BIOBASE_POS_JSON` lines are parsed into both `biobase_cs2_game_event` (type=`biobase_pos`) **and** `biobase_cs2_movement_sample`. `BIOBASE_EVENT_JSON` lines go only to `game_event` using the `"type"` field as `event_type`.

This design avoids any direct network connection from the CS2 plugin to Biobase — the entire bridge is the server's log stream. ^[inferred]

## Round Stats (JSON_BEGIN / JSON_END Blocks)

CS2 emits multi-line blocks at round start with cumulative per-player stats:
```
JSON_BEGIN{
  ... (lines without commas — not valid JSON, parsed via regex)
}}JSON_END
```
The parser accumulates lines between markers and extracts: `round_number`, `score_t`, `score_ct`, `map`, and per-player rows keyed by `"player_N"`. Fields are mapped to `biobase_cs2_round_stats` columns.

**Note:** CS2 omits commas between lines in this block, so `json.loads()` would fail. The parser uses `re.search()` per field instead.

## Bulk Parse Entry Point

`parse_events_from_lines([(session_id, raw_line), ...])` returns three lists:
- `game_events` → `biobase_cs2_game_event`
- `movement_samples` → `biobase_cs2_movement_sample`
- `round_stats_rows` → `biobase_cs2_round_stats`

## Related

- [[biobase-telemetry-schema]] — tables populated by this parser
- [[biobase-session-ingest]] — when parsing runs in the session lifecycle
- [[biobase]] — project overview
