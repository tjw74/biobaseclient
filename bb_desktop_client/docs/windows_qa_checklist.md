# Biobase Windows QA Checklist

Use this before calling the desktop client public-ready.

## Machine setup

- Windows 10/11
- Steam installed
- CS2 installed and logged into the user's Steam account
- CS2 video mode: borderless/windowed preferred
- A real `.dem` file from the Biobase CS2 server

## Build / install

1. Install dependencies with Node 20+.
2. Run `npm run dist:win:unsigned` for local QA or `npm run dist:win` when signing env vars are present.
3. Install or run the portable artifact from `release/`.

## Functional checks

- App starts without a console window.
- Demo auto-scan returns demos from the Steam CS2 folder, Documents, or Downloads.
- Manual `Import .dem` works if auto-scan finds nothing.
- Parsing does not freeze on large demos.
- Movement samples and player summaries populate.
- HUD overlay opens and stays above CS2 in borderless/windowed mode.
- HUD is click-through and does not steal mouse focus from CS2.
- Play/pause/+5s/-5s sync controls update dashboard and overlay together.
- API settings persist across restart.
- Device pairing stores a device id without exposing the token in UI.
- Upload queue persists failed uploads and clears after successful retry.

## Known limitation

Exclusive fullscreen may hide the overlay. The v1 supported playback mode is CS2 borderless/windowed.
