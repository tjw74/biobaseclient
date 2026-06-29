---
title: Wiki Index
updated: 2026-06-29T10:27:42Z
---

# Wiki Index

*Last updated: 2026-06-29T10:27:42Z*

## LLM updates (attribution)

Any **LLM** that changes this wiki must **name itself** on the edit, then apply the change:

1. Add a **Recent Activity** line in [[hot]] with `agent=<who>` (e.g. `agent=Composer` for Cursor’s Composer, `agent=Claude`, `agent=GPT-5`, or `agent=human` for a person).
2. Optionally set or bump `updated:` in the frontmatter of pages you touch.

Format: `[ISO8601] WIKI_UPDATE agent=<id> project=<biobase|meta|…> — <one-line summary>`

## Concepts

- [[llm-wiki-pattern]] — Karpathy LLM Wiki pattern; how raw sources, vault, and skills fit together ( #biobase #meta)
- [[zero-inference-labeling]] — Naming philosophy: every label communicates with zero cognitive inference from the user ( #design #ux #biobase)

## Entities

- [[andrej-karpathy]] — Author of the public LLM Wiki gist ( #person #llm-wiki)

## Skills

*No global skills yet.*

## References

- [[karpathy-llm-wiki-gist]] — Raw mirror of Karpathy gist in `docs/llm-wiki-raw/` ( #llm-wiki #source)
- [[repo-info-md]] — Distilled notes on repo `info.md` vs SQL schema layout ( #biobase #operators)

## Synthesis

*No synthesis yet.*

## Journal

*No journal entries yet.*

## Projects

### Biobase

- [Performance Review UI Doctrine](projects/biobase/concepts/biobase-performance-review-ui-doctrine.md) — Single-page review cockpit with persistent reorderable accordion sections, full metric inventories, and optional deep dives
- [Performance Dataset Contract](projects/biobase/concepts/biobase-performance-contract.md) — Versioned source, confidence, availability, scoring, and client-session persistence contract
- [Performance Dataset Roadmap](projects/biobase/concepts/biobase-performance-dataset-roadmap.md) — Canonical pro-player performance categories, metrics, and implementation phases
- [Biobase](projects/biobase/biobase.md) — CS2 game analytics platform overview
- [Session Ingest](projects/biobase/concepts/biobase-session-ingest.md) — session lifecycle, RCON polling, Loki query
- [Telemetry Schema](projects/biobase/concepts/biobase-telemetry-schema.md) — `public` / `ops` / `game` tables + CLI inspection
- [Log Parsing & Plugin Protocol](projects/biobase/concepts/biobase-log-parsing.md) — CS2 log format, BIOBASE_POS_JSON, event types
- [Hub Routing](projects/biobase/concepts/biobase-hub-routing.md) — nginx path routing, GF_SERVER_ROOT_URL, operator UI
- [Data Collection Prep](projects/biobase/skills/biobase-data-collection-prep.md) — CS2KZ unload, logging cvars, re-run after changelevel
- [BioBase CS2 Telemetry + Reconciliation](projects/biobase/concepts/biobase-cs2-telemetry-and-reconciliation.md) — FACEIT/game-plane JSON v1 bundle, ZSTD drop, reconcile stub + parser notes
- [Windows Client Primary UI](projects/biobase/concepts/biobase-windows-client-primary-ui.md) — Windows-first local Biobase client: CS2 desktop playback, overlay HUD, local demo parsing, stats dashboard, bio sensor capture, and central sync
- [Product Roadmap](projects/biobase/concepts/biobase-product-roadmap.md) — Phased delivery plan (Phase 1–3), progress tracking, current state v0.1.44
- [Replay Demo Playback](projects/biobase/concepts/biobase-replay-demo-playback.md) — CS2 as render engine; v0.11.27 adds console-toggle scan-code SendInput for exec/playdemo and treats Netcon as optional control attach after render command issue
