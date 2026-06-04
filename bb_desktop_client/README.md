# Biobase Client

Windows desktop client for Biobase CS2 demo review.

## Install on Windows

The test user should install Biobase with a single downloadable file.

1. Open this repo's **Actions** tab.
2. Open the latest successful **Windows Installer Build** run.
3. Download the artifact named **Biobase-Client-Setup**.
4. Unzip the artifact.
5. Double-click **Biobase-Client-Setup.exe**.
6. Follow the installer prompts.
7. Launch **Biobase Client** from the Start Menu or desktop shortcut.

No command line, Node.js, npm, or developer tools are required for the test user.

### Windows security warning

Early Biobase test builds are not code-signed yet. Windows SmartScreen may show:

```text
Windows protected your PC
```

For the private test build, choose:

```text
More info -> Run anyway
```

For public release we should add a Windows code-signing certificate so this warning goes away.

## First-run setup

1. Keep CS2 installed and logged into Steam normally.
2. Run CS2 in **borderless/windowed** mode for reliable overlay behavior.
3. Open Biobase Client.
4. Enter the Biobase API URL if provided by the test coordinator.
5. Enter the pairing code if provided.
6. Click **Scan demo folders** or **Import .dem**.
7. Select a demo and use the dashboard/HUD during local CS2 replay playback.

## What the app does

- imports local CS2 `.dem` files
- parses movement timeline data locally
- shows movement-first dashboard statistics
- renders a transparent always-on-top HUD over local CS2 replay playback
- keeps an offline upload queue for central Biobase sync
- stores device tokens encrypted with Electron `safeStorage` when OS encryption is available

## Product boundary

Biobase Client uses the user's own Windows desktop, Steam account, and CS2 install for replay playback. The central server stores account/session data and comparisons; it does not render CS2 replays.

## Current test-build limitations

- The installer is unsigned until we add a signing certificate.
- CS2 should be borderless/windowed; exclusive fullscreen may hide overlays.
- Playback sync is manual in v1.
- The production Biobase API must expose the documented pairing/upload endpoints.

## QA checklist

See `docs/windows_qa_checklist.md`.

---

# Developer setup

These commands are only for developers building the app from source. Test users should use the installer above.

## Install dependencies

```bash
npm ci
```

## Run in development

```bash
npm run dev
```

## Verify locally

```bash
npm run lint:config
npm run typecheck
npm test
npm run build
npm audit --omit=dev --audit-level=high
```

## Build Windows installer

```bash
npm run dist:win:installer:unsigned
```

The installer is written to `release/Biobase-Client-Setup-<version>-x64.exe`.

## API endpoints expected by this MVP

Device pairing:

```text
POST /api/client/device/pair
Content-Type: application/json
```

Response:

```json
{ "deviceId": "dev_...", "deviceToken": "tok_...", "accountName": "Player" }
```

Session upload:

```text
POST /api/client/sessions
Content-Type: application/json
```

The client sends `X-Biobase-Device-Id` and `X-Biobase-Device-Token` headers after pairing.
