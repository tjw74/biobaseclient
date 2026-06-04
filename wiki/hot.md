---
title: Hot Cache
updated: 2026-06-04T15:54:47Z
---

# Hot Cache

*A ~500-word semantic snapshot of recent activity. Updated after every major write operation. **LLM edits must include `agent=` on each line below** (see [[index]]).*

## Recent Activity

- [2026-06-04T16:25:00Z] WIKI_UPDATE agent=GPT-5.5 project=biobase — **Desktop client MVP finalization** — added persisted settings, upload queue/retry, clean TS build layout, and README release notes before local commit.
- [2026-06-04T16:07:39Z] WIKI_UPDATE agent=GPT-5.5 project=biobase — **Desktop client MVP implementation** — `bb_desktop_client` now includes local `.dem` scan/import, `@laihoe/demoparser2` parser integration, shared playback clock, HUD play/seek controls, parsed movement sample display, and structured upload stub to central Biobase API.
- [2026-06-04T15:54:47Z] WIKI_UPDATE agent=GPT-5.5 project=biobase — **Windows client primary UI** — Biobase user product pivots to local Windows client beside Steam/CS2: `.dem` detection/parsing, transparent overlay HUD, movement dashboard, future bio/EMG capture, and central structured-data sync; scaffolded `bb_desktop_client` and documented [[biobase-windows-client-primary-ui]]
- [2026-05-13T20:00:00Z] WIKI_UPDATE agent=Composer project=biobase — **CS2 telemetry v1 + reconcile stub** — `docs/cs2/biobase-telemetry-v1.{md,schema.json}`, `tools/biobase_demo_reconcile.py`, `bb_cs2_dashboard/.biobase/telemetry/` pointer; concept page [[biobase-cs2-telemetry-and-reconciliation]]
- [2026-05-11T21:20:00Z] WIKI_UPDATE agent=Composer project=biobase — **CS2 admin dashboard** (`bb_cs2_dashboard`): `/admin` FastAPI+Vite; **`POST /admin/api/uploads`** → `BB_CLIPS_HOST_DIR` (default `/mnt/backups/biobase/clips`) bind → `/data/clips`; NFS non-writable **`biobase/clips`** → **`apply-clips-bind.sh`** (bind **`biobase_clips_upload`**, `fstab` `bind,nofail`, legacy volume migrate) or **Proxmox** **`proxmox-chown-biobase-clips.sh`**; upload JSON **`vm_clips_path` + `host`**; docs: [[biobase-cs2-admin-dashboard]]
- [2026-05-11T12:00:00Z] WIKI_UPDATE agent=Composer project=biobase+meta — Enabled Karpathy LLM Wiki at **repo root**: `.cursor/rules/biobase-llm-wiki.mdc`, `AGENTS.md`, `.cursor/skills` → `obsidian-wiki/.skills`; raw gist → `docs/llm-wiki-raw/`; vault pages [[llm-wiki-pattern]], [[andrej-karpathy]], [[karpathy-llm-wiki-gist]], [[repo-info-md]]; `obsidian-wiki/.env.biobase.example` (+ local `.env`); [[biobase]] links pattern + Postgres container name note (`bb_postgres` vs local `dc_postgres`)
- [2026-04-29T18:00:00Z] WIKI_UPDATE agent=Composer (Cursor) project=biobase+meta — telemetry-schema: Postgres CLI (`psql`, `\dt *.*`, `\dn`); index blurb fix; movement in `game.biobase_cs2_movement_sample`; troubleshooting when only `public` exists
- [2026-04-29T12:00:00Z] WIKI_UPDATE agent=Composer (Cursor) project=meta — LLM attribution convention: `agent=` required on hot lines; documented on wiki index
- [2026-04-26T20:00:00Z] WIKI_UPDATE project=biobase — Grafana **Game data** dashboard: blue table column headers (theme primary); `GF_PANELS_DISABLE_SANITIZE_HTML` + Overview HTML `<style>`; wiki telemetry + overview adjusted
- [2026-04-26T12:00:00Z] WIKI_UPDATE project=biobase — Postgres **ops** vs **game** schemas documented (telemetry-schema, session-ingest, log-parsing, data-collection-prep, overview); session anchor stays in **public**
- [2026-04-28T07:00:00Z] WIKI_UPDATE project=biobase — 1 page created (data-collection-prep skills page), 2 updated (biobase overview + session-ingest)
- [2026-04-28T00:00:00Z] WIKI_UPDATE project=biobase — 5 pages created (overview + 4 concept pages)

## Active Threads

**Biobase** — CS2 game analytics platform in active development. Product direction is now **Windows desktop client first** for users: local CS2 replay, local `.dem` parsing, overlay HUD, movement stats dashboard, future bio/EMG sensor capture, and central upload/sync. Core server/admin ingest pipeline (RCON status + Loki log lines → Postgres **ops**; parsed gameplay + CS2KZ mirror → **game**) remains the operator/backend layer.

## Key Takeaways

**CS2KZ must be unloaded before data collection.** The KZ plugin hooks `bot_stop` and `mp_roundtime` in ways that prevent bots from moving and suppress round events. `short_match_rcon.sh` does `meta unload 1` + game-mode switch + enables logging — and must be re-run after every `changelevel` since the plugin reloads automatically on map change.

**The BIOBASE plugin protocol is the critical bridge for granular data.** RCON `status` only gives coarse server-wide data (player count, map, hostname). All per-player movement/combat telemetry requires CS2 server plugins printing `BIOBASE_POS_JSON` / `BIOBASE_EVENT_JSON` to console → Docker stdout → Loki → **`ops.biobase_cs2_log_line`** → parse → **`game`**. Without this, **`game.biobase_cs2_movement_sample`** and kill events are empty.

**Session architecture:** everything is FK'd to **`public.biobase_cs2_match_session`**. Raw ingest lives in **`ops`**; derived gameplay rows in **`game`**. Two start modes: hub (long-lived, browser-cancellable) and CLI (fixed-duration). Loki is queried for the session wall-clock window in one shot at the end — not streamed.

## Flagged Contradictions

- Root **`info.md`** narrates some tables without `ops.` / `game.` qualifiers; **live DDL** is in `bb_client/initdb/`. Resolved in [[repo-info-md]] and [[biobase-telemetry-schema]] — treat SQL + those pages as authoritative for schema, **`info.md`** for operator URLs and product narrative.

- Device pairing/auth headers and upload queue tests are implemented; remaining external step is GitHub deploy-key access/push plus real Windows CS2 QA.
