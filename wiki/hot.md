---
title: Hot Cache
updated: 2026-04-28T07:00:00Z
---

# Hot Cache

*A ~500-word semantic snapshot of recent activity. Updated after every major write operation.*

## Recent Activity

- [2026-04-28T07:00:00Z] WIKI_UPDATE project=biobase — 1 page created (data-collection-prep skills page), 2 updated (biobase overview + session-ingest)
- [2026-04-28T00:00:00Z] WIKI_UPDATE project=biobase — 5 pages created (overview + 4 concept pages)

## Active Threads

**Biobase** — CS2 game analytics platform in active development. Core ingest pipeline (RCON status + Loki log lines → Postgres) is working. Granular telemetry schema (player_snapshot, game_event, movement_sample, round_stats) is fully implemented with `log_parser.py` populating it from CS2 log lines. Latest addition: `short_match_rcon.sh` for preparing the CS2 server (CS2KZ unload + logging cvars) before collection runs.

## Key Takeaways

**CS2KZ must be unloaded before data collection.** The KZ plugin hooks `bot_stop` and `mp_roundtime` in ways that prevent bots from moving and suppress round events. `short_match_rcon.sh` does `meta unload 1` + game-mode switch + enables logging — and must be re-run after every `changelevel` since the plugin reloads automatically on map change.

**The BIOBASE plugin protocol is the critical bridge for granular data.** RCON `status` only gives coarse server-wide data (player count, map, hostname). All per-player movement/combat telemetry requires CS2 server plugins printing `BIOBASE_POS_JSON` / `BIOBASE_EVENT_JSON` to console → Docker stdout → Loki → ingest pipeline. Without this, `biobase_cs2_movement_sample` and kill events are empty.

**Session architecture:** everything is FK'd to `biobase_cs2_match_session`. Two start modes: hub (long-lived, browser-cancellable) and CLI (fixed-duration). Loki is queried for the session wall-clock window in one shot at the end — not streamed.

## Flagged Contradictions

*None yet.*
