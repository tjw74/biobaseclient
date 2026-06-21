---
title: BioBase Product Roadmap
category: concepts
tags: [biobase, roadmap, product, cs2]
sources: [projects/biobase]
summary: >-
  BioBase product roadmap: phased delivery from desktop client and phone
  companion (Phase 1) through performance dashboards and bio-sensor
  integration (Phase 2) to self-hosted server offering (Phase 3).
provenance:
  extracted: 0.90
  inferred: 0.08
  ambiguous: 0.02
created: 2026-06-21T23:00:00Z
updated: 2026-06-21T23:00:00Z
---

# BioBase Product Roadmap

BioBase is a CS2 performance analytics platform. The product has three UI surfaces and a server backend, delivered in phases.

## Three UI surfaces

1. **Desktop Client** (Electron, Windows-first) — the primary rich experience. Players install it on the same machine as CS2. It shows live movement stats, server status, game overlay, and demo playback with stats.
2. **Phone Companion** (React SPA at `/companion`) — a responsive phone mirror accessed via secret time-limited QR code from the desktop client. Same data, optimized for glancing while playing.
3. **Admin Dashboard** (React SPA at `/admin`) — operator-facing web UI for server management, demo uploads, map controls, observability, and the scrollytelling roadmap page.

## Phase 0: The Vision (Active)

The platform's two pillars: the client app players install, and the CS2 server that powers the data pipeline. The client is the primary experience; the companion is a phone-side mirror.

- Features: 2
- Status: Active

## Phase 1: Foundation (In Progress / Shipped)

### Desktop Client App — In Progress

The player's home base. Every control lives where the user is already looking. Core features:

- **Top bar controls**: server connection pill (map + player count, click for player list + Launch CS2), companion button (click for QR popover), overlay toggle
- **Movement panel**: dominant full-width element with speed, counter-strafe, path efficiency, tick, WASD keys — this is what users care about most
- **Playback tab**: demo file replay with stats overlay (renamed from "Review" per [[zero-inference-labeling]])
- **Game overlay**: transparent always-on-top HUD rendering movement stats directly on the CS2 screen
- **Auto-update**: click version number to check, downloads in background, one-click restart

Design principle: **extreme friction reduction**. Updates are automatic. Companion QR generates instantly (no player name required). Player tracking auto-detects from Steam. Every interaction that can be eliminated, is eliminated.

- Features: 6
- Status: In Progress
- Current version: 0.1.44

### Phone Companion — In Progress

Scan QR from the client, phone becomes a live stats display. Two responsive modes: full (tablets) and compact (phones). Same design language and component library as the desktop client. One codebase, responsive CSS adaptation.

- Features: 4
- Status: In Progress

### Auto-Update Pipeline — Shipped

Client checks for updates on launch and on version click. YAML manifest served from Caddy. electron-updater handles differential downloads, integrity verification, atomic installs. Cache-busted via Caddy headers.

- Features: 3
- Status: Shipped

## Phase 2: Analytics (Planned)

### Performance Dashboards — Planned

Purpose-built dashboards for each aspect of CS2 performance:

- **Movement**: speed patterns, counter-strafe timing, path efficiency, bhop consistency
- **Shooting**: accuracy breakdowns, spray control, crosshair placement, peek timing
- **Bio Sensors**: physiological data overlaid on game stats
- **Live Stats**: real-time combined view

Players select up to 3 focus categories; BioBase builds a combined dashboard on demand. Customizable and saveable.

- Features: 8
- Status: Planned

### Bio-Sensor Integration — Planned

Physiological data synced to the game clock: heart rate, grip pressure, micro-tremor patterns, all timestamped to the exact tick. Device pairs over USB or Bluetooth. Raw streams downsampled to match game tick rate.

- Features: 5
- Status: Planned

## Phase 3: Server Offering (Future)

### BioBase CS2 Server — Roadmap

Package the internal server stack for self-hosting by teams and players. Includes CS2 dedicated server with BioBase instrumentation, operator dashboard, data pipeline, and movement/shooting analysis backend.

- Features: 7
- Status: Roadmap

## Progress tracking

### Shipped (v0.1.44)

- [x] Electron desktop client with React renderer
- [x] Cross-compiled Windows NSIS installer from Linux
- [x] Auto-update pipeline (latest.yml + Caddy + electron-updater)
- [x] Live movement stats (speed, counter-strafe, path efficiency, tick, WASD keys)
- [x] Server status display (map, player count, click-to-track)
- [x] Game overlay HUD (transparent always-on-top window)
- [x] Phone companion via secret QR code (time-limited companion codes)
- [x] Demo file detection, import, local parsing
- [x] Playback tab with parsed timeline stats
- [x] Upload queue with retry for structured summaries
- [x] Admin dashboard with roadmap, overview, server controls, demo uploads
- [x] Movement data pipeline (BIOBASE_POS_JSON in Docker logs)
- [x] Companion-first onboarding (removed player name gate)
- [x] Compact top-bar UI (server pill, companion popover, overlay toggle)
- [x] Scrollytelling roadmap page in admin dashboard

### Next up

- [ ] Performance dashboards (movement, shooting)
- [ ] Bio-sensor device driver integration
- [ ] Pro movement partner integration
- [ ] Custom dashboard builder
- [ ] Server offering packaging

## Architecture reference

```
User's Windows machine
  ├── Steam / CS2
  └── BioBase Desktop Client (Electron)
        ├── Live tab → movement stats, server pill, companion QR, overlay toggle
        ├── Playback tab → demo files, parsed timeline, stats overlay
        ├── Game overlay → transparent HUD above CS2
        └── Auto-updater → YAML manifest from cs2.clarionlab.dev/client/

BioBase Server (Docker on ClarionCore)
  ├── bb_cs2_server → CS2 dedicated server + RCON
  ├── bb_cs2_dashboard → FastAPI + React admin at /admin, companion at /companion
  ├── bb_cs2_control → server control API
  └── cc_monitor_caddy → reverse proxy, static client files, update manifest

Phone
  └── Browser → cs2.clarionlab.dev/companion/c/{code} → live stats mirror
```

## Deployment

- Client installer: `cs2.clarionlab.dev/install` (Windows) / `cs2.clarionlab.dev/install-mac` (macOS)
- Admin dashboard: `cs2.clarionlab.dev/admin`
- Companion: `cs2.clarionlab.dev/companion/c/{companion_code}`
- Update manifest: `cs2.clarionlab.dev/client/latest.yml`
- Download hub: `cs2.clarionlab.dev/client`

## Related

- [[biobase]] — project hub
- [[biobase-windows-client-primary-ui]] — client architecture
- [[biobase-cs2-admin-dashboard]] — admin dashboard
- [[zero-inference-labeling]] — naming philosophy applied across all surfaces
