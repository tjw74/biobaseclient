---
title: Biobase Replay Demo Playback Architecture
category: concepts
tags: [biobase, cs2, demo-playback, gsi, netcon, replay]
sources: [projects/biobase]
summary: >-
  CS2 is the render engine for demo playback; BioBase stages demos inside the
  actual Steam CS2 library, writes a temporary CS2-owned cfg bootstrap,
  patches Steam CS2 LaunchOptions while Steam is closed so Netcon opens, then
  sends playdemo after CS2 is alive.
created: 2026-06-27T01:30:00Z
updated: 2026-07-01T07:35:26Z
---

# Biobase Replay Demo Playback Architecture

## Core Constraint

CS2 `.dem` files can only be rendered by CS2 itself via the `playdemo` console command. The Source 2 demo format (PBDEMS2) encodes game state snapshots, entity updates, and protobuf-encoded events against CS2's internal world representation. Building a custom render engine would mean reimplementing CS2's renderer — infeasible and unnecessary.

## Architecture Decision

CS2 is the render engine. BioBase is the companion controller.

```text
BioBase Flutter Client                    CS2 Client
┌──────────────────────┐                 ┌──────────────────┐
│  Replay UI           │                 │  Demo Playback   │
│  ├── Move marking    │  ──Netcon──►    │  ├── playdemo    │
│  ├── Playback ctrl   │   (TCP cmd)     │  ├── demo_pause  │
│  ├── Timeline/tick   │                 │  ├── demo_goto   │
│  └── Stats overlay   │  ◄───GSI────   │  └── game state  │
│                      │   (HTTP POST)   │                  │
└──────────────────────┘                 └──────────────────┘
```

## Integration Channels

### Netcon (BioBase → CS2)

CS2 client launched with `-netconport 2121` opens a TCP socket accepting console commands. BioBase connects and sends:

- `playdemo "<path>"` — start demo playback
- `demo_pause` / `demo_resume` — pause/resume
- `demo_gototick <tick>` — seek to specific tick
- `demo_timescale <float>` — playback speed (0.25x to 4x)

Netcon is now treated as an optional control channel. Initial demo rendering is started through Steam's documented launch-command URL path instead of waiting on Netcon.

### GSI (CS2 → BioBase)

Game State Integration is a CS2 client feature (already used by BioBase's Live screen). CS2 POSTs JSON game state to a local HTTP endpoint on configurable intervals. During demo playback, GSI reports:

- Current tick / timestamp
- Round number and phase
- Player states (position, health, equipment)
- Map name

BioBase's existing GSI receiver syncs the Replay UI timeline to CS2's actual playback position.

## Demo File Metadata

BioBase parses the PBDEMS2 header locally (no CS2 needed) to display demo info before playback:

- **Header** (first 2KB): map name, event/server name, network protocol, build number
- **FileInfo** (at offset stored in bytes 8-11): playback duration, tick count, frame count
- **Derived**: tickrate (ticks / duration), typically 64 tick for pro demos

This parsing uses raw protobuf field decoding — no `.proto` compilation required. See `demo_parser.dart`.

## Pro Demo Pipeline

HLTV pro demos are scraped server-side by `biobasedata` (Python + Playwright), stored on ClarionCore, and served via REST API. The BioBase client downloads individual map demos (~300-900 MB each) to `%APPDATA%/BioBase/demos/`. See the biobasedata service at `cs2.clarionlab.dev/biobasedata`.

## Netcon Launch Option: Implementation Challenges

The `-netconport 2121` launch option must be passed to CS2 at startup. This proved to be the primary integration blocker across v0.11.15–v0.11.21 (six iterations). Every approach to pass the argument through Steam's launch system failed silently — Steam accepts the commands without error but does not forward the extra arguments to CS2.

### Approaches Attempted (all failed to open port 2121)

| Version | Approach | Why It Failed |
|---------|----------|---------------|
| v0.11.15 | Write `-netconport 2121` to `localconfig.vdf` while Steam is running | Steam caches VDF in memory; overwrites file on exit, discarding the write |
| v0.11.16 | `steam.exe -applaunch 730 -netconport 2121` | Steam does not forward extra args after the app ID to the game process |
| v0.11.17 | Same as above + kill CS2 first to ensure clean launch | Same result — Steam strips the extra arguments |
| v0.11.18 | `steam://run/730/-netconport%202121//` URL protocol | Used the wrong URL shape for Steamworks launch command line and only tested a Netcon option, not the full replay command |
| v0.11.19 | Kill Steam → write VDF → restart Steam → launch CS2 | `hasNetconLaunchOption()` found stale VDF entry from v0.11.15 write, skipped the Steam restart |
| v0.11.20 | Same as v0.11.19 but always restart Steam (removed stale-file check); fixed VDF parser whitespace bug | VDF `_injectNetconOption()` had hardcoded `\t\t` in `replaceFirst` — silently failed when actual file used different whitespace. Fixed with position-based replacement, but Steam still did not reliably pass launch options to CS2 |

### Key Technical Discoveries

**Steam caches `localconfig.vdf` in memory.** Writing to the file while Steam is running is useless — Steam overwrites it with its in-memory version on exit. You must kill Steam first, write the file, then restart Steam.

**Steam's `-applaunch` does not forward extra arguments.** When you run `steam.exe -applaunch 730 -netconport 2121`, Steam interprets `-applaunch 730` but silently drops `-netconport 2121`. This is true whether Steam is already running (IPC to existing instance) or launched fresh.

**Steam URL argument shape matters.** Steamworks documents `steam://run/<appid>//<command line>/` as the launch-command path. The earlier Replay attempt used `steam://run/730/-netconport%202121//`, which put the command in the wrong path segment for the documented form and did not include the actual `+playdemo` replay command.

**VDF parsing is fragile.** Steam's Valve Data Format uses inconsistent whitespace (tabs vs spaces, varying depth). Hardcoded whitespace patterns in string replacement silently produce unchanged output. Position-based replacement (using regex match offsets) is required.

**The file-check false positive.** `hasNetconLaunchOption()` searches the VDF for the string `-netconport`. If a previous failed write put this string in the file (but Steam never loaded it), the check returns true and the critical Steam restart is skipped. The setting exists in the file but not in Steam's running config.

### Current Approach (v0.11.31): Persistent Steam LaunchOptions + Netcon Post-Launch Command

v0.11.30 proved the demo and cfg are landing in the correct CS2 install, but CS2 can still remain on the menu. That means the startup command path is not reliable enough: Steam app args can be stripped and CS2 startup/autoexec timing can miss `playdemo`. v0.11.31 therefore moves the critical command delivery to Netcon after CS2 is alive by forcing Steam itself to launch CS2 with BioBase LaunchOptions.

```text
1. Resolve the actual CS2 install from Steam `libraryfolders.vdf` / `appmanifest_730.acf` before falling back to legacy guesses.
2. Copy selected demo → <CS2>/game/csgo/biobase_replays/<safe-name>.dem.
3. Write <CS2>/game/csgo/cfg/biobase_replay.cfg containing:
   con_enable "1"
   echo "BioBase Replay bootstrap: launching demo"
   playdemo biobase_replays/<safe-name>.dem
   demo_resume
4. Patch <CS2>/game/csgo/cfg/autoexec.cfg with the marker-delimited BioBase block as a secondary path.
5. Close CS2.
6. Close Steam, patch each Steam account `userdata/*/config/localconfig.vdf` app `730` LaunchOptions while Steam is not running, and add/normalize:
   -console -condebug -netconport 2121 +exec biobase_replay
7. Restart Steam silently.
8. Launch CS2 through `steam.exe -applaunch 730`.
9. Wait up to 45 seconds for Netcon to open, then send `playdemo <staged-demo>` through the socket after CS2 is alive.
10. Keep the replay cfg cleanup timer so the persistent `+exec biobase_replay` becomes harmless on later launches.
```

What changed in v0.11.31:

- **Steam must be closed before patching LaunchOptions.** Steam caches `localconfig.vdf`, so v0.11.31 intentionally closes Steam before writing CS2 app `730` LaunchOptions.
- **Netcon is now the primary render command path.** The persistent LaunchOptions are designed to open `-netconport 2121`; once the socket opens, BioBase sends `playdemo` post-launch instead of hoping startup args execute at the right time.
- **The replay cfg remains useful but is no longer the only path.** `+exec biobase_replay` is persisted; the cfg contains the selected demo during the launch window and is later overwritten with a no-op.
- **LaunchOptions are idempotent and preserve user options.** BioBase keeps existing options, normalizes any old `-netconport`, and appends only the BioBase control args.
- **Replay waits longer after launch.** The control-socket wait is now 45 seconds because Steam may need to restart before CS2 starts.

**Status: v0.11.31 is the current Windows QA build.** The persistent Steam LaunchOptions added are:

```text
-console -condebug -netconport 2121 +exec biobase_replay
```

The post-launch Netcon command remains:

```text
playdemo biobase_replays/<demo>.dem
```

### GSI Config Auto-Install

The GSI config file (`gamestate_integration_biobase.cfg`) is written automatically to CS2's cfg directory. This uses Valve KeyValues format (not JSON) and is picked up by CS2 on next launch:

```
"BioBase"
{
    "uri"          "http://127.0.0.1:29741"
    "timeout"      "5.0"
    "buffer"       "0.1"
    "throttle"     "0.5"
    "heartbeat"    "10.0"
    "data"
    {
        "provider"              "1"
        "map"                   "1"
        "round"                 "1"
        "player_id"             "1"
        "player_state"          "1"
        "allplayers_id"         "1"
        "allplayers_state"      "1"
        "allplayers_position"   "1"
    }
}
```

## User Flow

1. User opens Replay, selects a demo (local, server, or pro)
2. BioBase parses the PBDEMS2 header → shows map, event, duration, tickrate
3. User clicks "Watch in CS2" → BioBase resolves the Steam library containing CS2, stages the file under `game/csgo/biobase_replays`, writes `biobase_replay.cfg`, patches the BioBase autoexec marker, closes Steam to patch CS2 app `730` LaunchOptions, restarts Steam, launches CS2, waits for Netcon, then sends `playdemo` after CS2 is alive
4. CS2 renders the demo; BioBase attaches controls through Netcon and GSI streams game state back
5. BioBase timeline syncs to CS2 tick position
6. User marks move start/end in BioBase UI, synced to CS2's game clock
7. Marked moves are saved with tick positions for use in other features (Shadow, analysis)

## What BioBase Does NOT Do

- Does not render 3D game world
- Does not parse full demo event streams client-side (server-side parsing planned for stats)
- Does not replace CS2's demo player — it augments it

## Related

- [[biobase-windows-client-primary-ui]] — client-first architecture
- [[biobase-performance-review-ui-doctrine]] — UI design principles
- [[biobase-product-roadmap]] — feature roadmap
