---
title: Biobase Replay Demo Playback Architecture
category: concepts
tags: [biobase, cs2, demo-playback, gsi, netcon, replay]
sources: [projects/biobase]
summary: >-
  CS2 is the render engine for demo playback; BioBase is the companion
  controller using Netcon (TCP console) for commands and GSI for game
  state. No custom render engine needed or planned.
created: 2026-06-27T01:30:00Z
updated: 2026-06-27T01:30:00Z
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

## User Flow

1. User opens Replay, selects a demo (local, server, or pro)
2. BioBase parses the PBDEMS2 header → shows map, event, duration, tickrate
3. User clicks "Watch in CS2" → BioBase launches CS2 with netcon enabled and sends `playdemo`
4. CS2 renders the demo; GSI streams game state back to BioBase
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
