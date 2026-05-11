---
title: Repo info.md (operator map)
category: references
tags: [biobase, operators, architecture]
sources: [info.md]
summary: >-
  High-level map of Biobase stacks, hub URLs, data flow, and gaps vs granular
  telemetry; cross-check schema details with bb_client initdb migrations.
provenance:
  extracted: 0.92
  inferred: 0.06
  ambiguous: 0.02
created: 2026-05-11T12:00:00Z
updated: 2026-05-11T12:00:00Z
---

# Repo `info.md` (operator map)

**Source:** `info.md` at repository root (human-oriented narrative).

## What it covers well

- **Operator entry:** hub URL (default **`:8880`**), nginx paths (`/bb/`, `/loki/`, `/cs2/`, `/data/`), `GF_SERVER_ROOT_URL`.
- **Data flow today:** hub → `bb_cs2_control` + `bb_data_collection`; Loki window ingest; **coarse** RCON `status` vs **raw** log lines.
- **Gaps:** granular movement / combat requires explicit capture (plugins, structured log lines, or new ingest), as **`status` alone is insufficient**.

## Schema caveat

`info.md` sometimes names tables without **`ops.` / `game.`** qualifiers. The **implemented** layout is in `bb_client/initdb/*.sql` (session anchor in **`public`**, RCON + log lines in **`ops`**, parsed gameplay / CS2KZ mirror in **`game`**). For detail see [[biobase-telemetry-schema]].

## Related

- [[biobase]]
- [[biobase-hub-routing]]
- [[biobase-session-ingest]]
