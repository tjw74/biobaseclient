import electron from 'electron';
const { BrowserWindow, dialog, globalShortcut, screen } = electron;
import { pathToFileURL } from 'node:url';
import type { ClientSettings } from '../shared/types.js';
import {
  applySingleVirtualDesktopPolicy,
  watchVirtualDesktopIsolation,
  type VirtualDesktopWatch,
} from './windowsDesktopIsolation.js';

/** Hard caps — overlay must never exceed these dimensions. */
export const OVERLAY_MAX_WIDTH = 480;
export const OVERLAY_MAX_HEIGHT = 280;
export const OVERLAY_DEFAULT_WIDTH = 420;
export const OVERLAY_DEFAULT_HEIGHT = 220;
export const OVERLAY_MARGIN = 16;

/** Auto-close overlay after 4 hours even if shortcuts fail. */
export const OVERLAY_MAX_LIFETIME_MS = 4 * 60 * 60 * 1000;
/** Close overlay if main window has not heartbeated within this window. */
export const OVERLAY_HEARTBEAT_STALE_MS = 60 * 1000;
export const OVERLAY_HEARTBEAT_CHECK_MS = 10 * 1000;

export const OVERLAY_ESCAPE_SHORTCUT = 'Escape';
export const OVERLAY_TOGGLE_SHORTCUT = 'CommandOrControl+Shift+O';
export const OVERLAY_QUIT_SHORTCUT = 'CommandOrControl+Shift+Q';
export const RELEASE_MOUSE_SHORTCUT = 'CommandOrControl+Shift+M';

let overlayUserOptedIn = false;

export function setOverlayUserOptedIn(optedIn: boolean): void {
  overlayUserOptedIn = optedIn;
}

export function isOverlayKillSwitchActive(): boolean {
  const raw = (process.env.BIOBASE_DISABLE_OVERLAY ?? '').trim().toLowerCase();
  return raw === '1' || raw === 'true' || raw === 'yes';
}

export function isOverlayEnvForceEnabled(): boolean {
  const raw = (process.env.BIOBASE_ENABLE_OVERLAY ?? '').trim().toLowerCase();
  return raw === '1' || raw === 'true' || raw === 'yes';
}

/** Overlay off by default until first HUD confirmation or BIOBASE_ENABLE_OVERLAY=1. */
export function isOverlayFeatureDisabled(): boolean {
  if (isOverlayKillSwitchActive()) return true;
  if (isOverlayEnvForceEnabled()) return false;
  return !overlayUserOptedIn;
}

/** Tray / Show HUD — blocked only by kill switch, not default-off policy. */
export function canInitiateOverlay(): boolean {
  return !isOverlayKillSwitchActive();
}

export function clampOverlaySize(width: number, height: number): { width: number; height: number } {
  return {
    width: Math.min(Math.max(1, Math.floor(width)), OVERLAY_MAX_WIDTH),
    height: Math.min(Math.max(1, Math.floor(height)), OVERLAY_MAX_HEIGHT),
  };
}

/** Position within workArea so the taskbar stays reachable. */
export function overlayBoundsForWorkArea(
  workArea: Electron.Rectangle,
  width = OVERLAY_DEFAULT_WIDTH,
  height = OVERLAY_DEFAULT_HEIGHT,
): Electron.Rectangle {
  const size = clampOverlaySize(width, height);
  const x = workArea.x + workArea.width - size.width - OVERLAY_MARGIN;
  const y = workArea.y + OVERLAY_MARGIN;
  return { x, y, width: size.width, height: size.height };
}

function assertSafeOverlayBounds(bounds: Electron.Rectangle, workArea: Electron.Rectangle) {
  if (bounds.width > OVERLAY_MAX_WIDTH || bounds.height > OVERLAY_MAX_HEIGHT) {
    throw new Error(`overlay exceeds max size (${bounds.width}x${bounds.height})`);
  }
  if (bounds.width >= workArea.width || bounds.height >= workArea.height) {
    throw new Error('overlay must not cover full work area (fullscreen guard)');
  }
  if (bounds.x < workArea.x || bounds.y < workArea.y) {
    throw new Error('overlay must stay inside workArea (taskbar guard)');
  }
  if (bounds.x + bounds.width > workArea.x + workArea.width) {
    throw new Error('overlay extends past workArea right edge');
  }
  if (bounds.y + bounds.height > workArea.y + workArea.height) {
    throw new Error('overlay extends past workArea bottom edge');
  }
}

export type OverlaySafetyDeps = {
  preloadPath: string;
  rendererUrl: (route: string) => string;
  getSettings: () => Promise<ClientSettings>;
  saveSettings: (patch: Partial<ClientSettings>) => Promise<ClientSettings>;
  getDashboardWindow: () => InstanceType<typeof BrowserWindow> | null;
  quitApp: () => void;
  releaseMouseCapture: () => Promise<{ ok: true } | { ok: false; error: string }>;
};

export type OverlayController = {
  isDisabled: () => boolean;
  isVisible: () => boolean;
  recordMainHeartbeat: () => void;
  registerGlobalSafetyShortcuts: () => void;
  unregisterGlobalSafetyShortcuts: () => void;
  showOverlay: () => Promise<void>;
  hideOverlay: () => void;
  toggleOverlay: () => Promise<void>;
  closeOnMainWindowClosed: () => void;
};

export function createOverlayController(deps: OverlaySafetyDeps): OverlayController {
  let overlayWindow: InstanceType<typeof BrowserWindow> | null = null;
  let lastMainHeartbeatMs = Date.now();
  let maxLifetimeTimer: ReturnType<typeof setTimeout> | null = null;
  let heartbeatWatchTimer: ReturnType<typeof setInterval> | null = null;
  let desktopWatch: VirtualDesktopWatch | null = null;

  function clearOverlayTimers() {
    if (maxLifetimeTimer) {
      clearTimeout(maxLifetimeTimer);
      maxLifetimeTimer = null;
    }
    if (heartbeatWatchTimer) {
      clearInterval(heartbeatWatchTimer);
      heartbeatWatchTimer = null;
    }
    desktopWatch?.stop();
    desktopWatch = null;
  }

  function hideOverlay() {
    clearOverlayTimers();
    if (overlayWindow && !overlayWindow.isDestroyed()) {
      const win = overlayWindow;
      overlayWindow = null;
      win.close();
      return;
    }
    overlayWindow = null;
  }

  function startOverlayTimers() {
    clearOverlayTimers();
    maxLifetimeTimer = setTimeout(() => {
      console.warn('[biobase-overlay] auto-closing after max lifetime (4h)');
      hideOverlay();
    }, OVERLAY_MAX_LIFETIME_MS);

    heartbeatWatchTimer = setInterval(() => {
      if (!overlayWindow || overlayWindow.isDestroyed()) return;
      const dashboard = deps.getDashboardWindow();
      if (!dashboard || dashboard.isDestroyed()) {
        console.warn('[biobase-overlay] main window gone — closing overlay');
        hideOverlay();
        return;
      }
      if (Date.now() - lastMainHeartbeatMs > OVERLAY_HEARTBEAT_STALE_MS) {
        console.warn('[biobase-overlay] main heartbeat stale — closing overlay');
        hideOverlay();
      }
    }, OVERLAY_HEARTBEAT_CHECK_MS);
  }

  async function confirmFirstHudUse(): Promise<boolean> {
    const settings = await deps.getSettings();
    if (settings.overlayHudConfirmed) return true;

    const { response } = await dialog.showMessageBox({
      type: 'warning',
      buttons: ['Cancel', 'Show HUD'],
      defaultId: 0,
      cancelId: 0,
      title: 'Show Biobase HUD?',
      message: 'The HUD is a small floating widget for remote coaching only.',
      detail:
        'Remote play: CS2 launches windowed/borderless so Esc opens the menu and frees the mouse.\n\n' +
        'Overlay is click-through — it does not steal your mouse.\n\n' +
        'Stuck? Ctrl+Shift+M sends Esc · Ctrl+Shift+O toggles overlay · Ctrl+Shift+Q quits app.',
      noLink: true,
    });
    if (response !== 1) return false;

    await deps.saveSettings({ overlayHudConfirmed: true });
    return true;
  }

  async function createOverlayWindow() {
    if (!canInitiateOverlay()) {
      console.warn('[biobase-overlay] overlay blocked via BIOBASE_DISABLE_OVERLAY');
      return;
    }
    if (!(await confirmFirstHudUse())) return;
    setOverlayUserOptedIn(true);

    if (overlayWindow && !overlayWindow.isDestroyed()) {
      overlayWindow.focus();
      return;
    }

    const display = screen.getPrimaryDisplay();
    const workArea = display.workArea;
    const bounds = overlayBoundsForWorkArea(workArea);
    assertSafeOverlayBounds(bounds, workArea);

    overlayWindow = new BrowserWindow({
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: bounds.height,
      maxWidth: OVERLAY_MAX_WIDTH,
      maxHeight: OVERLAY_MAX_HEIGHT,
      fullscreen: false,
      fullscreenable: false,
      frame: false,
      transparent: true,
      backgroundColor: '#00000000',
      resizable: false,
      movable: true,
      hasShadow: true,
      // Never set alwaysOnTop in the constructor on Windows — apply after single-desktop policy.
      ...(process.platform === 'win32' ? {} : { alwaysOnTop: true }),
      skipTaskbar: false,
      focusable: false,
      show: false,
      ...(process.platform === 'darwin' ? { type: 'panel' as const } : {}),
      title: 'Biobase HUD',
      webPreferences: {
        preload: deps.preloadPath,
        contextIsolation: true,
        nodeIntegration: false,
      },
    });

    overlayWindow.setFullScreen(false);
    overlayWindow.setMaximumSize(OVERLAY_MAX_WIDTH, OVERLAY_MAX_HEIGHT);
    overlayWindow.setBackgroundColor('#00000000');
    applySingleVirtualDesktopPolicy(overlayWindow, { alwaysOnTop: true });
    desktopWatch = watchVirtualDesktopIsolation(overlayWindow, () => {
      console.warn('[biobase-overlay] virtual desktop changed — closing HUD');
      hideOverlay();
    });

    overlayWindow.once('ready-to-show', () => {
      overlayWindow?.setIgnoreMouseEvents(true, { forward: true });
      overlayWindow?.showInactive();
    });
    overlayWindow.on('closed', () => {
      overlayWindow = null;
      clearOverlayTimers();
    });

    recordMainHeartbeat();
    startOverlayTimers();
    await overlayWindow.loadURL(deps.rendererUrl('/overlay'));
  }

  function recordMainHeartbeat() {
    lastMainHeartbeatMs = Date.now();
  }

  function registerShortcut(shortcut: string, handler: () => void) {
    if (globalShortcut.isRegistered(shortcut)) return;
    const registered = globalShortcut.register(shortcut, handler);
    if (!registered) {
      console.warn(`[biobase-overlay] failed to register globalShortcut ${shortcut}`);
    }
  }

  function unregisterShortcut(shortcut: string) {
    if (globalShortcut.isRegistered(shortcut)) {
      globalShortcut.unregister(shortcut);
    }
  }

  function registerGlobalSafetyShortcuts() {
    registerShortcut(OVERLAY_ESCAPE_SHORTCUT, () => hideOverlay());
    registerShortcut(OVERLAY_QUIT_SHORTCUT, () => {
      hideOverlay();
      deps.quitApp();
    });
    registerShortcut(OVERLAY_TOGGLE_SHORTCUT, () => {
      void toggleOverlay();
    });
    registerShortcut(RELEASE_MOUSE_SHORTCUT, () => {
      void deps.releaseMouseCapture();
    });
  }

  function unregisterGlobalSafetyShortcuts() {
    unregisterShortcut(OVERLAY_ESCAPE_SHORTCUT);
    unregisterShortcut(OVERLAY_TOGGLE_SHORTCUT);
    unregisterShortcut(OVERLAY_QUIT_SHORTCUT);
    unregisterShortcut(RELEASE_MOUSE_SHORTCUT);
  }

  async function toggleOverlay() {
    if (!canInitiateOverlay()) return;
    if (overlayWindow && !overlayWindow.isDestroyed()) {
      hideOverlay();
      return;
    }
    await createOverlayWindow();
  }

  return {
    isDisabled: isOverlayFeatureDisabled,
    isVisible: () => Boolean(overlayWindow && !overlayWindow.isDestroyed()),
    recordMainHeartbeat,
    registerGlobalSafetyShortcuts,
    unregisterGlobalSafetyShortcuts,
    showOverlay: createOverlayWindow,
    hideOverlay,
    toggleOverlay,
    closeOnMainWindowClosed: hideOverlay,
  };
}

/** Exported for tests — builds a file URL like main process renderer loader. */
export function rendererIndexUrl(indexPath: string, route: string): string {
  const hash = route.startsWith('/') ? route : `/${route}`;
  return `${pathToFileURL(indexPath).href}#${hash}`;
}
