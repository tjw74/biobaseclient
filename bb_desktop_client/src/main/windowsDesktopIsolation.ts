import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import electron from 'electron';

const { app, BrowserWindow } = electron;
type BrowserWindowInstance = InstanceType<typeof BrowserWindow>;

const LOG_PREFIX = '[biobase-desktop]';
const DESKTOP_WATCH_MS = 1_000;
const APP_USER_MODEL_ID = 'com.biobase.client';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function isolationScriptPath(): string {
  const candidates = [
    path.join(app.getAppPath(), 'scripts/windows/virtual-desktop-isolation.ps1'),
    path.join(__dirname, '../../scripts/windows/virtual-desktop-isolation.ps1'),
    path.join(__dirname, '../../../scripts/windows/virtual-desktop-isolation.ps1'),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return candidates[0];
}

export function hwndFromBrowserWindow(win: BrowserWindowInstance): number {
  const handle = win.getNativeWindowHandle();
  if (process.platform === 'win32') {
    return handle.readInt32LE(0);
  }
  return 0;
}

function runWindowsIsolation(action: 'unpin' | 'is-on-current', hwnd: number): string {
  const script = isolationScriptPath();
  if (!fs.existsSync(script)) {
    throw new Error(`virtual desktop isolation script missing: ${script}`);
  }
  return execFileSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script,
      '-Action',
      action,
      '-Hwnd',
      String(hwnd),
      '-AppId',
      APP_USER_MODEL_ID,
    ],
    { encoding: 'utf8', windowsHide: true, timeout: 10_000 },
  ).trim();
}

export function unpinFromAllVirtualDesktops(hwnd: number): void {
  if (process.platform !== 'win32' || hwnd === 0) return;
  try {
    runWindowsIsolation('unpin', hwnd);
  } catch (error) {
    console.warn(`${LOG_PREFIX} failed to unpin hwnd=${hwnd} from all virtual desktops`, error);
  }
}

export function isWindowOnCurrentVirtualDesktop(hwnd: number): boolean {
  if (process.platform !== 'win32' || hwnd === 0) return true;
  try {
    return runWindowsIsolation('is-on-current', hwnd).toLowerCase() === 'true';
  } catch (error) {
    console.warn(`${LOG_PREFIX} failed to read virtual desktop for hwnd=${hwnd}`, error);
    return true;
  }
}

/**
 * Keep a window on the current virtual desktop only. Never pin to all workspaces/desktops.
 * On Windows, use the mildest always-on-top level that does not span virtual desktops.
 */
export function applySingleVirtualDesktopPolicy(
  win: BrowserWindowInstance,
  options?: { alwaysOnTop?: boolean },
): void {
  win.setVisibleOnAllWorkspaces(false);

  if (process.platform === 'win32') {
    const hwnd = hwndFromBrowserWindow(win);
    unpinFromAllVirtualDesktops(hwnd);
    if (options?.alwaysOnTop) {
      // 'floating' / 'screen-saver' can follow the user across Win11 virtual desktops.
      win.setAlwaysOnTop(true, 'normal');
    }
    return;
  }

  if (options?.alwaysOnTop) {
    win.setAlwaysOnTop(true, 'floating');
  }
}

export type VirtualDesktopWatch = {
  stop: () => void;
};

/** Close overlay when the user switches away from the desktop where it was opened. */
export function watchVirtualDesktopIsolation(
  win: BrowserWindowInstance,
  onLeftDesktop: () => void,
): VirtualDesktopWatch | null {
  if (process.platform !== 'win32') return null;

  const hwnd = hwndFromBrowserWindow(win);
  let stopped = false;
  const timer = setInterval(() => {
    if (stopped || win.isDestroyed()) return;
    if (!isWindowOnCurrentVirtualDesktop(hwnd)) {
      console.warn(`${LOG_PREFIX} window left current virtual desktop — closing`);
      onLeftDesktop();
    }
  }, DESKTOP_WATCH_MS);

  return {
    stop: () => {
      if (stopped) return;
      stopped = true;
      clearInterval(timer);
    },
  };
}

/** Unpin the whole app once at startup so new windows are not cloned onto every desktop. */
export function unpinAppFromAllVirtualDesktopsOnStartup(): void {
  if (process.platform !== 'win32' || !app.isReady()) return;
  const [firstWindow] = BrowserWindow.getAllWindows();
  if (!firstWindow || firstWindow.isDestroyed()) return;
  unpinFromAllVirtualDesktops(hwndFromBrowserWindow(firstWindow));
}
