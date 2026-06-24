# Overlay safety — postmortem rules

Biobase Client v0.1.24 and earlier shipped a **fullscreen transparent overlay** with `alwaysOnTop: 'screen-saver'`. On Windows this could trap operators: Task Manager, Alt+Tab, and the taskbar became unreachable. **Never ship that pattern again.**

v0.1.27 shipped a small HUD but still used `alwaysOnTop: 'floating'` without Windows virtual-desktop isolation. On Windows 11, always-on-top Electron windows can appear as a **black rectangle on every virtual desktop** (including newly created desktops), trapping users who use Win+Tab workspaces. Fixed in **v0.1.28**.

## What must never ship

| Forbidden | Why |
|-----------|-----|
| Fullscreen or workArea-sized overlay windows | Covers the entire desktop; no escape without killing the process |
| `alwaysOnTop: 'screen-saver'` or higher | Blocks Task Manager and system UI on Windows |
| `alwaysOnTop: 'floating'` on Windows overlay | Can follow the user across Win11 virtual desktops |
| `setVisibleOnAllWorkspaces(true)` or leaving pin-to-all-desktops unset | Pins HUD (or whole app) to every virtual desktop |
| `skipTaskbar: true` on overlay | Hides from Alt+Tab and taskbar; harder to find and close |
| Overlay shortcuts registered only while overlay is open | If overlay hangs before registration, user has no global kill switch |
| Overlay with no max lifetime | Zombie overlay can outlive the main window |
| Overlay without main-window heartbeat | Orphan HUD survives dashboard crash |
| Auto-opening HUD on startup, desktop switch, or new virtual desktop | User must explicitly opt in via tray/sidebar |

## Required guards (v0.1.28+)

1. **Size:** max 480×280, positioned in `workArea` (taskbar visible), `skipTaskbar: false`, `fullscreenable: false`.
2. **Z-order:** macOS/Linux: `setAlwaysOnTop(true, 'floating')`. Windows: `setAlwaysOnTop(true, 'normal')` only — never `'floating'` or `'screen-saver'`.
3. **Single virtual desktop (Windows):** `setVisibleOnAllWorkspaces(false)` on overlay **and** main window; unpin via `IVirtualDesktopPinnedApps`; close HUD when user leaves the desktop where it was opened.
4. **Global shortcuts at app start:** Esc closes HUD, Ctrl+Shift+O toggles HUD, Ctrl+Shift+Q quits app.
5. **Auto-close:** 4 h max lifetime; close when main window closes; close if main heartbeat stale >60 s.
6. **First use:** confirmation dialog (remote-only warning) before first HUD show.
7. **Kill switch env:** `BIOBASE_DISABLE_OVERLAY=1` blocks all overlay creation. **Default off** until first HUD confirmation; override with `BIOBASE_ENABLE_OVERLAY=1` for legacy auto-enable.
8. **One HUD instance:** reuse or close — never spawn per desktop.

Implementation lives in `src/main/overlaySafety.ts` and `src/main/windowsDesktopIsolation.ts`. All overlay creation must go through `createOverlayController()`.

## Failure mode: black window on every virtual desktop (v0.1.27)

**Symptom:** User creates or switches Win11 virtual desktops (Desktop 1, 2, 3…) and sees a black Biobase window on each; cannot escape without killing the process.

**Cause:** Always-on-top overlay (constructor `alwaysOnTop: true` + `setAlwaysOnTop(..., 'floating')`) was not explicitly unpinned from Windows virtual desktops. Windows treated the Electron top-level window as visible on all desktops.

**Fix (v0.1.28):** `applySingleVirtualDesktopPolicy()` + `watchVirtualDesktopIsolation()`; Windows uses `'normal'` always-on-top; PowerShell helper calls `IVirtualDesktopPinnedApps.UnpinView` / `UnpinAppID`.

## If a user is trapped (legacy build)

1. **Ctrl+Shift+Q** — quits entire app (v0.1.27+).
2. **Ctrl+Shift+O** or **Esc** — close/toggle HUD (v0.1.24+ small widget; older builds may vary).
3. Tray icon → **Close HUD** or **Quit Biobase**.
4. Remote **close_overlay** command from Biobase admin.
5. Task Manager → end **Biobase Client** (may be blocked on very old fullscreen builds — use SSH/RDP to run `taskkill /IM "Biobase Client.exe" /F`).
6. Win+Tab → right-click Biobase window → **Close window**; uncheck **Show windows from this app on all desktops** if pinned.

## QA checklist

- [ ] HUD is a small top-right widget, not fullscreen
- [ ] Taskbar and Task Manager remain reachable with HUD open
- [ ] Esc / Ctrl+Shift+O / Ctrl+Shift+Q work before and after HUD opens
- [ ] Closing main window closes HUD
- [ ] `BIOBASE_DISABLE_OVERLAY=1` hides HUD controls and blocks creation
- [ ] HUD does **not** appear on startup
- [ ] Creating Win11 virtual desktop 2/3 does **not** show Biobase HUD there
- [ ] Switching virtual desktop while HUD is open closes HUD (or HUD stays only on original desktop)
- [ ] Main dashboard stays on its own desktop only (not cloned to every desktop)
