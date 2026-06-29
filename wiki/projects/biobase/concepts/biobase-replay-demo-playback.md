---
title: Biobase Replay Demo Playback Architecture
category: concepts
tags: [biobase, cs2, demo-playback, gsi, netcon, replay]
sources: [projects/biobase]
summary: >-
  CS2 is the render engine for demo playback; BioBase stages demos inside the
  CS2 game tree, writes a replay cfg, launches CS2 with +exec/+playdemo,
  then uses Netcon or a Windows console fallback for playback control.
created: 2026-06-27T01:30:00Z
updated: 2026-06-29T10:06:49Z
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

This replaces the unreliable `steam://` protocol URL approach for launching demos.

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
| v0.11.18 | `steam://run/730/-netconport%202121//` URL protocol | Steam URL handler does not pass arguments to the game |
| v0.11.19 | Kill Steam → write VDF → restart Steam → launch CS2 | `hasNetconLaunchOption()` found stale VDF entry from v0.11.15 write, skipped the Steam restart |
| v0.11.20 | Same as v0.11.19 but always restart Steam (removed stale-file check); fixed VDF parser whitespace bug | VDF `_injectNetconOption()` had hardcoded `\t\t` in `replaceFirst` — silently failed when actual file used different whitespace. Fixed with position-based replacement, but Steam still did not reliably pass launch options to CS2 |

### Key Technical Discoveries

**Steam caches `localconfig.vdf` in memory.** Writing to the file while Steam is running is useless — Steam overwrites it with its in-memory version on exit. You must kill Steam first, write the file, then restart Steam.

**Steam's `-applaunch` does not forward extra arguments.** When you run `steam.exe -applaunch 730 -netconport 2121`, Steam interprets `-applaunch 730` but silently drops `-netconport 2121`. This is true whether Steam is already running (IPC to existing instance) or launched fresh.

**Steam's `steam://run/` URL protocol also drops arguments.** The format `steam://run/730/-netconport%202121//` is documented to support arguments, but in practice the game receives none.

**VDF parsing is fragile.** Steam's Valve Data Format uses inconsistent whitespace (tabs vs spaces, varying depth). Hardcoded whitespace patterns in string replacement silently produce unchanged output. Position-based replacement (using regex match offsets) is required.

**The file-check false positive.** `hasNetconLaunchOption()` searches the VDF for the string `-netconport`. If a previous failed write put this string in the file (but Steam never loaded it), the check returns true and the critical Steam restart is skipped. The setting exists in the file but not in Steam's running config.

### Current Approach (v0.11.26): Stage Demo + Replay CFG + Console-Open SendInput Injection

Windows QA of v0.11.22-v0.11.25 showed CS2 could be opened from BioBase and the demo could be staged, but the command handoff was still the failing seam: direct `+playdemo` was not a reliable startup contract, Netcon did not open on the target machine, and v0.11.25 could report a successful SendInput run without proving the CS2 console was actually open. v0.11.26 therefore treats initial rendering as a console-command delivery problem rather than a Netcon dependency.

```text
1. Copy selected demo → <CS2>/game/csgo/biobase_replays/<safe-name>.dem
2. Write <CS2>/game/csgo/cfg/biobase_replay.cfg containing:
   con_enable "1"
   bind "`" "toggleconsole"
   bind "F8" "toggleconsole"
   playdemo biobase_replays/<safe-name>.dem
   demo_resume
3. Launch cs2.exe directly with:
   -steam -novid -console -dev -condebug -windowed -noborder -netconport 2121 +exec biobase_replay.cfg +playdemo biobase_replays/<safe-name>.dem
4. Wait for Netcon on 127.0.0.1:2121; if connected, resend playdemo and attach pause/seek/speed controls
5. If Netcon does not open after 8 seconds, force-focus CS2 with PowerShell/Win32, send command passes before and after console-toggle (`VK_OEM_3`), and inject `exec biobase_replay` plus `playdemo <staged-demo>` via both clipboard paste and direct Unicode `SendInput`
6. Stop blocking initial rendering on Netcon: if command injection runs, mark the render command as issued, retry Netcon in the background for controls, and surface diagnostics that distinguish command handoff from socket attach
```

This is intentionally layered rather than elegant because Replay is a release-critical value proposition:

- **Demo file staging:** CS2 receives a relative path under its own `game/csgo` tree, matching the already-used render-worker pattern of copying demos into the game directory before `playdemo`.
- **Replay cfg bootstrap:** `biobase_replay.cfg` lets CS2 execute `playdemo` after the client config system exists, which is more reliable than only passing a one-shot launch command.
- **Launch-time redundancy:** BioBase passes both `+exec biobase_replay.cfg` and `+playdemo <staged-demo>` so either command path can start rendering.
- **Windows console fallback:** if CS2 opens but ignores startup commands, BioBase force-focuses the CS2 window, attempts command delivery in the current console state, toggles the developer console with `VK_OEM_3`, and repeats delivery using both clipboard paste and direct Unicode `SendInput`. This fixes the v0.11.25 flaw where input could be sent to the CS2 window without the console being open.
- **Control attach:** Netcon remains the preferred control channel for pause/resume/timescale/seek, but it is no longer treated as required for the first render. After fallback command issue, the UI stops spinning and background-retries Netcon so controls attach if the socket appears.
- **Diagnostics:** Replay surfaces the exact failure stage instead of spinning: staging, replay cfg, GSI config, CS2 launch, Netcon timeout, console fallback, or command send.

**Status: v0.11.26 is the current Windows QA build.** v0.11.25 proved that lower-level `SendInput` alone was not enough because the CS2 console might not be open/focused; the app could say “typed” while CS2 stayed in the menu. v0.11.26 adds explicit console-toggle multi-pass injection, `-dev`, replay-cfg console bindings, and a UI state fix so Netcon absence does not masquerade as render failure once `playdemo` has been issued.

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
3. User clicks "Watch in CS2" → BioBase stages the file under `game/csgo/biobase_replays`, writes `biobase_replay.cfg`, launches CS2 with `+exec`/`+playdemo`, and waits for Netcon
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
