# Mac dev setup (Biobase Client)

Use this on your Mac laptop while Windows test machines are unavailable. Same codebase as the Windows client — no separate Mac product build required.

## Prerequisites

1. **Node.js 22+** and npm (`node -v`, `npm -v`)
2. **Steam + CS2** installed on the Mac
3. Clone or pull this repo on the Mac

## Run the client

```bash
cd bb_desktop_client
npm ci
npm run dev
```

Two windows launch:

- **Biobase Client** — dashboard (demos, parse, settings)
- After you click **Show HUD** — small floating widget (top-right), not fullscreen

Leave the terminal open while developing. Press `Ctrl+C` to stop.

## CS2 + overlay workflow

1. In CS2 video settings, use **Windowed** or **Borderless windowed** (not exclusive fullscreen).
2. Start CS2 (match, practice, or demo replay).
3. In Biobase Client, click **Import .dem** or wait for auto-scan after CS2 is installed.
4. Select a demo → **Parse selected demo**.
5. Click **Show HUD Overlay**.
6. Alt-tab to CS2 — the HUD should sit on top. Use dashboard **Play/Pause** and **±5s** to sync timeline manually (v1).

## Demo auto-scan paths (macOS)

The client scans:

- `~/Library/Application Support/Steam/steamapps/common/Counter-Strike Global Offensive/game/csgo`
- `~/Library/Application Support/Steam/steamapps/common/Counter-Strike 2/game/csgo`
- `.../csgo/replays` under those installs
- `~/Documents` and `~/Downloads`

## If the overlay does not appear over CS2

1. Confirm CS2 is **not** in exclusive fullscreen.
2. Click **Show HUD Overlay** again after CS2 is running.
3. macOS **System Settings → Privacy & Security → Screen Recording** — allow **Electron** / **Biobase Client** if macOS prompts.
4. Hide overlay from the dashboard (**Hide HUD**) before quitting.

## What is not validated on Mac

Windows installer, SmartScreen, and final player QA still require a Windows PC. Mac dev is for UI, parsing, overlay layout, and API work only.

## Verify before pushing

```bash
npm run typecheck
npm test
```
