---
title: Biobase Windows Client Primary UI
category: concepts
tags: [biobase, cs2, windows-client, overlay-hud, demo-analysis]
sources: [projects/biobase]
summary: Windows-first Biobase client architecture: local CS2 playback, local demo parsing, overlay HUD, stats dashboard, bio sensor capture, and central server sync.
created: 2026-06-04T15:54:47Z
updated: 2026-06-04T16:25:00Z
---

# Biobase Windows Client Primary UI

Biobase's user-facing product should be a **Windows desktop client**, not primarily a website. The local client runs on the same desktop as Steam/CS2, which makes demo playback and HUD overlay design much cleaner than trying to render CS2 on headless Linux or embed VNC in a dashboard.

## Product architecture

```text
User Windows desktop
  ├── Steam / CS2
  ├── Biobase desktop client
  │     ├── local .dem detection/storage
  │     ├── demo parser + tick/time timeline
  │     ├── overlay HUD window above CS2
  │     ├── movement stats dashboard
  │     ├── bio/EMG sensor capture later
  │     └── central upload/sync agent
  └── local Biobase cache

Central Biobase server
  ├── accounts/auth
  ├── CS2 server connection metadata
  ├── uploaded parsed match/session data
  ├── uploaded bio sensor data
  ├── aggregate comparison baselines
  └── admin/operator dashboards
```

## Why this is the right design

- Steam auth stays with the user.
- CS2 rendering happens in the user's real desktop environment.
- No VNC/noVNC product path.
- No server-side GPU/render bottleneck.
- Overlay HUD is feasible because the Biobase client runs locally beside CS2.
- Demo parsing and bio sensor capture can be local-first, then synced centrally.
- The server becomes a data/coordination layer rather than a remote desktop renderer.

## Local client responsibilities

1. Help the user connect to the Biobase CS2 server.
2. Detect, save, or import local `.dem` files.
3. Parse `.dem` files into movement/events/tick timeline data.
4. Display a replay/movement stats dashboard.
5. Render a transparent always-on-top HUD over CS2 playback.
6. Capture bio/EMG sensor input later and align it to the demo timeline.
7. Upload structured match/session summaries, timelines, and sensor data to the central Biobase server.

## HUD implementation direction

Use a separate transparent desktop window, not CS2 process injection.

```text
CS2 replay window
  + Biobase always-on-top transparent HUD window
```

Initial assumptions:

- Windows-first.
- CS2 should run borderless/windowed for reliable overlay behavior.
- HUD is click-through during playback.
- HUD pulls from local parsed timeline data and optional sensor streams.
- Avoid anti-cheat risk by not injecting into CS2.

## Sync model

The demo data is timestamped/tick-indexed, so the parsed analytics timeline is straightforward. The local client still needs a playback clock for the overlay. V1 can use a simple local playback/session clock and manual resync controls; later versions can improve detection of pause, seek, round jump, and demo playback state.

## Server responsibilities

The central Biobase server should receive structured data, not raw desktop streams:

- user account and machine identity
- match/session metadata
- parsed movement timeline summaries
- raw/derived bio sensor samples where appropriate
- comparison-ready aggregates
- optional raw demo/video artifacts if product requirements call for them

## First implementation target

Create `bb_desktop_client` as an Electron + React Windows client scaffold with:

- user dashboard shell
- overlay HUD window foundation
- typed match/timeline contracts
- mock movement timeline
- central sync configuration placeholder
- GitHub Actions Windows build workflow

Related pages: [[biobase]], [[biobase-cs2-admin-dashboard]], [[biobase-cs2-telemetry-and-reconciliation]].

## Implementation status - 2026-06-04

`bb_desktop_client` now has an Electron + React MVP foundation:

- Windows desktop shell and transparent always-on-top HUD window.
- Local `.dem` scan/import/select flow.
- Local copy into Electron `userData/demos`.
- Node `@laihoe/demoparser2` parser integration for header/tick movement extraction with metadata fallback.
- Shared playback clock with play/pause/seek controls used by dashboard and overlay.
- Movement HUD values mapped from parsed timeline samples when available.
- Persisted client settings and durable upload queue/retry for structured summaries to `/api/client/sessions`.
- Windows GitHub Actions packaging workflow.

Remaining product hardening: signed Windows installer, real Biobase central API endpoint/auth, sensor device drivers, better CS2 playback-state detection, and live Windows overlay QA against borderless CS2.

## Release-hardening implementation status

Updated 2026-06-04T17:45:00Z:

- Added device pairing flow via `POST /api/client/device/pair`.
- Uploads now include device auth headers when paired.
- Added persisted client credentials/settings.
- Added Node test suite for API URL/auth helpers and demo path sanitization.
- Upgraded Electron/electron-builder and separated runtime/dev dependencies; production audit is clean.
- Added Windows QA checklist and verified Linux-side Windows unpacked packaging (`dist:win:dir`).
- GitHub push remains intentionally pending until deploy key access is added.

## v0.1.42–0.1.44 UI redesign (2026-06-21)

Three major changes shipped in rapid succession:

### v0.1.42: Companion onboarding fix
- Removed player name requirement from companion QR code generation.
- Users can now generate the companion link with one click — no name input needed.
- Player tracking auto-detects from Steam or can be set by clicking a player in the server list.

### v0.1.43: Architecture redesign
- Desktop client established as the **primary rich UI** with 2-column grid layout.
- Phone companion rebuilt as a **responsive phone mirror** — same data, optimized for glancing.
- Companion web app reduced from swipeable multi-page to single scrollable view.
- Shared design language between desktop and companion (same CSS class names, color tokens, component patterns).

### v0.1.44: Compact top-bar UI
- **Server panel removed as standalone card** → compact server pill in top bar showing map name + player count. Click expands dropdown with player list (click-to-track) and "Launch CS2" button.
- **Companion panel removed as standalone card** → phone icon button in top bar. Click opens floating popover with auto-generated QR code and copy link.
- **Session panel removed** ("Play on Biobase" button confused users — it just launched CS2 via steam:// protocol). Launch CS2 moved to server dropdown. Player tracking and share stats moved to Advanced.
- **Overlay toggle** added to top bar as compact on/off pill.
- **Movement panel now full-width and dominant** — larger stat numbers (26px), bigger WASD keys. This is what users care about most.
- **"Review" tab renamed to "Playback"** per [[zero-inference-labeling]] — "Review" required users to infer purpose ("review what?"), "Playback" states it directly.

### Current UI layout (v0.1.44)

```
Top bar: [Biobase v0.1.44] [Live] [Playback]  ...  [server-pill ▾] [📱] [Overlay] [●]
─────────────────────────────────────────────────────────────────────────
Main area (Live tab):
  ┌─────────────────────────────────────────────────────────────────┐
  │ MOVEMENT                                                 LIVE  │
  │ ┌──────────┬───────────────┬────────────────┬──────────┐       │
  │ │   250    │     0.55      │      0.70      │ 5190887  │       │
  │ │  SPEED   │ COUNTER-STRAFE│ PATH EFFICIENCY│   TICK   │       │
  │ └──────────┴───────────────┴────────────────┴──────────┘       │
  │ [W] [A] [S] [D] [JUMP] [DUCK]                                  │
  └─────────────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────────────┐
  │ SHOOTING                                                 SOON  │
  │ Coming in a future update.                                      │
  └─────────────────────────────────────────────────────────────────┘
  ▸ Advanced
  ─────────────────────────────────────────────────────────────────
  status line
```

### Design decisions documented

- [[zero-inference-labeling]] — naming philosophy applied to all UI labels
- [[biobase-product-roadmap]] — full roadmap with progress tracking

Related pages: [[biobase]], [[biobase-cs2-admin-dashboard]], [[biobase-cs2-telemetry-and-reconciliation]].

