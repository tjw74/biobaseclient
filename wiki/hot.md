---
title: Hot Cache
updated: 2026-04-26T20:00:00Z
---

# Hot Cache

*A ~500-word semantic snapshot of recent activity. Updated after every major write operation.*

## Recent Activity

- [2026-04-26T20:00:00Z] WIKI_UPDATE project=biobase — Grafana **Game data** dashboard: blue table column headers (theme primary); `GF_PANELS_DISABLE_SANITIZE_HTML` + Overview HTML `<style>`; wiki telemetry + overview adjusted
- [2026-04-26T12:00:00Z] WIKI_UPDATE project=biobase — Postgres **ops** vs **game** schemas documented (telemetry-schema, session-ingest, log-parsing, data-collection-prep, overview); session anchor stays in **public**
- [2026-04-28T07:00:00Z] WIKI_UPDATE project=biobase — 1 page created (data-collection-prep skills page), 2 updated (biobase overview + session-ingest)
- [2026-04-28T00:00:00Z] WIKI_UPDATE project=biobase — 5 pages created (overview + 4 concept pages)

## Active Threads

**Biobase** — CS2 game analytics platform in active development. Core ingest pipeline (RCON status + Loki log lines → Postgres **ops**; parsed gameplay + CS2KZ mirror → **game**) is working. Grafana dashboards split: **Ops ingest** (`ops.*`) vs **Game data** (`game.*`). Migration `007` + app startup DDL move legacy `public.*` tables into the right schema before creating new ones.

## Key Takeaways

**CS2KZ must be unloaded before data collection.** The KZ plugin hooks `bot_stop` and `mp_roundtime` in ways that prevent bots from moving and suppress round events. `short_match_rcon.sh` does `meta unload 1` + game-mode switch + enables logging — and must be re-run after every `changelevel` since the plugin reloads automatically on map change.

**The BIOBASE plugin protocol is the critical bridge for granular data.** RCON `status` only gives coarse server-wide data (player count, map, hostname). All per-player movement/combat telemetry requires CS2 server plugins printing `BIOBASE_POS_JSON` / `BIOBASE_EVENT_JSON` to console → Docker stdout → Loki → **`ops.biobase_cs2_log_line`** → parse → **`game`**. Without this, **`game.biobase_cs2_movement_sample`** and kill events are empty.

**Session architecture:** everything is FK'd to **`public.biobase_cs2_match_session`**. Raw ingest lives in **`ops`**; derived gameplay rows in **`game`**. Two start modes: hub (long-lived, browser-cancellable) and CLI (fixed-duration). Loki is queried for the session wall-clock window in one shot at the end — not streamed.

## Flagged Contradictions

*None yet.*
