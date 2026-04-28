---
title: Hot Cache
updated: 2026-04-28T00:00:00Z
---

# Hot Cache

*A ~500-word semantic snapshot of recent activity. Updated after every major write operation.*

## Recent Activity

- [2026-04-28T00:00:00Z] WIKI_UPDATE project=biobase — 5 pages created (overview + 4 concept pages)

## Active Threads

**Biobase** — CS2 game analytics platform in active development. Core ingest pipeline (RCON status + Loki log lines → Postgres) is working. Granular telemetry tables (player_snapshot, game_event, movement_sample, round_stats) are defined but depend on CS2 server plugins emitting `BIOBASE_POS_JSON` / `BIOBASE_EVENT_JSON` log lines. Log parser (`log_parser.py`) and schema (`schema_cs2.py`) were the most recent additions.

## Key Takeaways

**The BIOBASE plugin protocol is the critical bridge for granular data.** RCON `status` only gives coarse server-wide data (player count, map, hostname). All per-player movement/combat telemetry requires CS2 server plugins that print structured JSON to console using the `BIOBASE_POS_JSON` / `BIOBASE_EVENT_JSON` prefixes — these then flow through Docker logs → Loki → ingest pipeline into Postgres. Without plugins using this protocol, `biobase_cs2_movement_sample` and `biobase_cs2_game_event` (kill events) will be empty.

**Session architecture:** everything is FK'd to `biobase_cs2_match_session`. Two start modes: hub (long-lived, browser-cancellable) and CLI (fixed-duration). Loki is queried for the session wall-clock window in one shot rather than streamed — simplifies implementation but means log lines arrive after-the-fact.

## Flagged Contradictions

*None yet.*
