---
title: >-
  Biobase Data Collection Prep (CS2 Server)
category: skills
tags: [cs2, game-analytics, rcon, cs2kz, operational]
sources: [projects/biobase]
summary: >-
  How to configure bb_cs2_server for a bot-deathmatch data collection session:
  unload CS2KZ, set game mode, enable logging, re-run after map change.
provenance:
  extracted: 0.90
  inferred: 0.08
  ambiguous: 0.02
created: 2026-04-28T07:00:00Z
updated: 2026-04-28T07:00:00Z
---

# Biobase Data Collection Prep (CS2 Server)

Before starting an ingest session the CS2 server must be configured for standard bot-deathmatch play. Use `bb_cs2_server/short_match_rcon.sh` on the host with `bb_cs2_server` already running.

## What the Script Does

```bash
./bb_cs2_server/short_match_rcon.sh
```

1. **Unloads CS2KZ** (`meta unload 1`) — the KZ plugin hooks `mp_roundtime ↔ mp_timelimit` sync and forces `bot_stop 1`, which would prevent bots from moving. Unloading is required before any cvar overrides take effect.
2. **Switches game mode** from KZ custom (`game_type 3`) to casual (`game_type 0, game_mode 0`) so bots fight with standard round logic.
3. **Unfreezes bots**: `bot_stop 0`, `bot_join_after_player 0`.
4. **Sets timing**: `mp_roundtime 2`, `mp_freezetime 0`, `mp_halftime 0`, `mp_timelimit 0`, `mp_match_end_changelevel 0`.
5. **Enables event logging**: `log on`, `sv_logecho 1`, `mp_logdetail 3`.

## Critical Caveat: Re-run After Map Change

`meta unload 1` only persists until the next map load. CS2KZ reloads automatically on `changelevel`. After any map change you must re-run `short_match_rcon.sh` before starting another ingest session, otherwise:
- bots will be frozen again (`bot_stop 1`)
- game mode reverts to KZ
- `sv_logecho` may be off → no log lines flow into Loki → `biobase_cs2_game_event` will be empty

## Logging Cvars Required for Ingest

| Cvar | Value | Effect |
|---|---|---|
| `log` | `on` | Enable server game-event log output |
| `sv_logecho` | `1` | Echo log lines to server console (→ Docker stdout → Loki) |
| `mp_logdetail` | `3` | Log damage events (`attacked` lines) — needed for per-shot granular data |

Without these, `bb_data_collection` will ingest an empty Loki window for the session.

## CS2 `status` Player Parsing

`bb_cs2_server/control/app.py` exposes `GET /api/status` which includes a `players` list. The parser (`parse_players()`) handles two row formats from RCON `status`:

```
# Bot:    "   0      BOT    0    0     active      0 'BotName '"
# Human:  "   2    12:45   45    0     active 196608 '1.2.3.4:27005' 'HumanName'"
```

Strategy: the `time_or_bot` field is `"BOT"` for bots; the **last** single-quoted field is always the player name. Humans have an optional IP-address field before their name. The regex makes the address field optional so both formats are matched without branching. Bots get `steamid="BOT"`.

## Sequence for a Collection Run

1. Confirm `bb_cs2_server` is up (`docker compose ps`)
2. Run `./bb_cs2_server/short_match_rcon.sh`
3. Wait ~10 s for bots to start fighting
4. Start session via hub UI or `tools/run_ingest_session.sh`
5. After session ends: verify `biobase_cs2_game_event` has `kill` rows (non-zero means logging worked)

## Related

- [[biobase-session-ingest]] — what happens once the session starts
- [[biobase-log-parsing]] — how log lines become game_events
- [[biobase]] — project overview
