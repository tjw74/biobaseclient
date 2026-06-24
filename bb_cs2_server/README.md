# bb_cs2_server

Docker stack for the CS2 dedicated server (`joedwards32/cs2`), **`bb_cs2_control`** (RCON REST API), and **`bb_cs2_dashboard`**.

## Profiles (`BB_CS2_SERVER_PROFILE`)

The container **`pre.sh`** hook chooses how much of the legacy “practice / CS2KZ” bundle to install and which config runs at boot. Set **`BB_CS2_SERVER_PROFILE`** in Compose (or **`bb_cs2_server/.env`**) alongside other CS2 vars.

| Value | Default? | Meaning |
|------|----------|---------|
| **`play`** | yes | **Standard combat:** Metamod + CounterStrikeSharp + BiobasePosEmitter + **[MatchZy](https://github.com/shobhit-pathak/MatchZy)** (practice / veto / replay-friendly match admin) — **CS2KZ and SQL_MM are not extracted**. Boots **`biobase_play.cfg`** (+ **`biobase_autostart.cfg`** for `mp_warmup_end`). Uses **`game_type 0`** / **`game_mode 0`** and clears dev-style cvars (infinite ammo, regen, `mp_ignore_round_win_conditions`, etc.). |
| **`practice`** or **`kz`** | no | **Legacy developer stack:** installs **CS2KZ + SQL_MM**, applies KZ server config, boots **`biobase_dev.cfg`** (cheat-friendly practice settings). |

**Startup chain:** Compose sets **`CS2_ADDITIONAL_ARGS`** to **`+exec biobase_startup`**. `pre.sh` writes **`cfg/biobase_startup.cfg`** to either `exec biobase_dev` or `exec biobase_play` / `exec biobase_autostart`. **`server.cfg`** always ends with **`exec biobase_startup`** so map loads re-apply the same profile.

**Cheat mode:** **`CS2_CHEATS`** is passed through to the image (default **`0`** in Compose). `biobase_play.cfg` does **not** force `sv_cheats`; use **`CS2_CHEATS=1`** when you need dev cheats on a play-mode server.

**Switching profiles on an existing data volume:** If **`play`** was used first, no KZ files exist — good. If you previously used **`practice|kz`**, the named volume may still contain **`addons/cs2kz`**; Metamod can keep loading it. For a clean **`play`** server, recreate the CS2 data volume or remove KZ/SQL_MM from `game/csgo/addons` inside the volume.

**MatchZy (`BB_CS2_ENABLE_MATCHZY`, default `1`):** The image bundles **`MatchZy-0.8.14.zip`** (plugin-only release; pinned SHA in `Dockerfile`). `pre.sh` unpacks into `game/csgo/addons/counterstrikesharp/plugins/MatchZy/` after CounterStrikeSharp is present. **`css_plugins list`** should list MatchZy once the dedicated server finishes boot — the dashboard aggregates that via **`GET /api/capabilities`** (substring `matchzy`) on **`bb_cs2_control`**. Set **`BB_CS2_ENABLE_MATCHZY=0`** (or `false` / `no` / `off`) to skip unpacking on constrained servers.

**Control API:** **`POST /api/bots/start`** on **`bb_cs2_control`** already sends **`mp_warmup_end`** (and logging cvars) after bot setup — no profile-specific change required.

**Capability probes:** **`bb_cs2_control`** uses **`mcrcon`**; multi-word CS2 commands (e.g. **`meta version`**, **`meta list`**, **`css_plugins list`**) must be sent as **one command line**. The bundled FastAPI helper joins `*parts` accordingly so **`GET /api/capabilities`** sees MatchZy/CSS output reliably.

### Enable the old KZ / dev profile

In **`bb_cs2_server/.env`** (or your Compose override):

```bash
BB_CS2_SERVER_PROFILE=practice
CS2_CHEATS=1
```

Then rebuild/recreate the server container so **`pre.sh`** runs against the image with the new env.

## Quick reference

- **Compose file:** `docker-compose.yml`
- **Configs in image:** `cfg/biobase_dev.cfg`, `cfg/biobase_play.cfg`, `cfg/biobase_autostart.cfg`, `cfg/gamemode_competitive_server.biobase.cfg` (copies to `gamemode_competitive_server.cfg` and delegates `exec biobase_startup`)
- **RCON scripts:** `rcon.sh`, `short_match_rcon.sh`, `start_bots_rcon.sh` (if present)
