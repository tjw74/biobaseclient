# Biobase Desktop Client

Windows-first Biobase client for CS2 users.

## Product role

The desktop client is the primary user UI for Biobase:

- detect/import local `.dem` files from the user's CS2/Steam environment
- parse demo timelines locally with `@laihoe/demoparser2`
- show a movement-first user dashboard
- render a transparent always-on-top HUD above local CS2 demo playback
- keep a manual playback clock for pause/seek sync in the first release
- queue structured session summaries for central Biobase upload
- leave bio/EMG sensor capture as the next local-device module

The central server owns accounts, durable session storage, team/global comparisons, and shared dashboards. It does **not** render CS2 replays.

## Development

```bash
npm install
npm run dev
```

## Production build

```bash
npm run lint:config
npm run build
```

## Windows package

```bash
npm run dist:win
```

Artifacts are written to `release/`.

## Runtime settings

The app stores settings and upload queue state under Electron `userData`.

Configurable in-app:

- API base URL, for example `https://biobase.live`
- device name
- server name

Upload endpoint expected by the MVP:

```text
POST /api/client/sessions
Content-Type: application/json
```

Payload shape:

```json
{
  "kind": "biobase-client-demo-summary",
  "version": 1,
  "deviceName": "player-pc",
  "serverName": "Biobase CS2",
  "uploadedAt": "2026-06-04T00:00:00.000Z",
  "parsed": { "sha256": "...", "movementSamples": [] }
}
```

## Overlay constraints

- Avoid CS2 process injection.
- Prefer a separate transparent always-on-top click-through overlay window.
- CS2 should run borderless/windowed for reliable overlay behavior.
- Exclusive fullscreen may hide desktop overlay windows.
- Manual sync controls are intentional for v1; later replace/augment with safe playback-state detection.

## Current MVP boundaries

Implemented:

- Electron main/preload/renderer split with renderer Node access disabled
- local demo scan/import/select
- content hash and app-controlled demo copy
- demoparser2 movement extraction with metadata fallback
- dashboard + HUD over a shared playback clock
- persisted settings
- durable upload queue with retry
- Windows packaging workflow

Still required before public user release:

- signed Windows installer
- production central API/auth/device pairing
- live Windows QA over CS2 borderless replay playback
- richer movement metrics and comparison baselines
- bio/EMG module
