import electron from 'electron';
const { app, BrowserWindow, ipcMain, Menu, nativeImage, screen, Tray } = electron;
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { importDemo, parseDemo, scanLocalDemos, selectDemoFile } from './demoService.js';
import type { ClientSettings } from '../shared/types.js';
import { getSettings, getUploadQueue, pairDevice, resetSettings, saveSettings, syncUploadQueue, uploadParsedSummary } from './uploadService.js';
import { fetchLiveStatus, getCachedLiveStatus, startLivePolling, stopLivePolling } from './liveService.js';
import {
  fetchLiveMovement,
  getCachedLiveMovement,
  setMovementTracking,
  startMovementPolling,
  stopMovementPolling,
} from './movementService.js';
import {
  checkForUpdates,
  configureUpdateFeed,
  downloadUpdate,
  getUpdateStatus,
  installUpdate,
  openManualInstallPage,
  openManualInstallMacPage,
  setupAutoUpdater,
  triggerAppUpdate,
} from './updateService.js';
import { startRemoteCommandPolling } from './remoteCommandService.js';
import { startPresencePolling, sendPresenceOnce } from './presenceService.js';
import { startRemoteWatchdog } from './watchdogService.js';
import { createCompanionLink } from './companionService.js';
import { connectToCs2Server, copyConnectCommand, createCs2DesktopShortcut, isCs2Running } from './cs2ConnectService.js';
import { releaseMouseCapture } from './remoteInputService.js';
import {
  canInitiateOverlay,
  createOverlayController,
  isOverlayFeatureDisabled,
  isOverlayKillSwitchActive,
  setOverlayUserOptedIn,
} from './overlaySafety.js';
import { applySingleVirtualDesktopPolicy, unpinAppFromAllVirtualDesktopsOnStartup } from './windowsDesktopIsolation.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let dashboardWindow: InstanceType<typeof BrowserWindow> | null = null;
let tray: InstanceType<typeof Tray> | null = null;

const overlay = createOverlayController({
  preloadPath: path.join(__dirname, 'preload.cjs'),
  rendererUrl,
  getSettings,
  saveSettings,
  getDashboardWindow: () => dashboardWindow,
  quitApp: () => app.quit(),
  releaseMouseCapture,
});

function trayIcon() {
  const dataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAANElEQVQ4T2NkYGD4z0ABYBzVMKoBBjABBg0GDAwM/5nQeBiGUTeMagAAAABJRU5ErkJggg==';
  return nativeImage.createFromDataURL(dataUrl);
}

function setupTray() {
  if (tray) return;
  tray = new Tray(trayIcon());
  tray.setToolTip(`Biobase Client ${app.getVersion()}`);
  const menuItems: Electron.MenuItemConstructorOptions[] = [];
  if (canInitiateOverlay()) {
    menuItems.push(
      {
        label: 'Show HUD',
        click: () => {
          void overlay.showOverlay();
        },
      },
      {
        label: 'Close HUD',
        click: () => {
          overlay.hideOverlay();
        },
      },
      { type: 'separator' },
    );
  }
  menuItems.push({
    label: 'Quit Biobase',
    click: () => {
      overlay.hideOverlay();
      app.quit();
    },
  });
  tray.setContextMenu(Menu.buildFromTemplate(menuItems));
}

const playbackState = {
  matchId: 'local-demo',
  demoPath: '',
  startedAtMs: Date.now(),
  offsetSec: 18,
  playing: true,
};

function currentTimeSec() {
  return playbackState.offsetSec + (playbackState.playing ? (Date.now() - playbackState.startedAtMs) / 1000 : 0);
}

function publicSettings<T extends { deviceToken?: string }>(settings: T): Omit<T, 'deviceToken'> {
  const { deviceToken: _deviceToken, ...safeSettings } = settings;
  return safeSettings;
}

function rendererUrl(route: string) {
  const devUrl = process.env.VITE_DEV_SERVER_URL;
  if (devUrl) return `${devUrl}${route}`;
  const hash = route.startsWith('/') ? route : `/${route}`;
  const indexPath = path.join(__dirname, '../renderer/index.html');
  return `${pathToFileURL(indexPath).href}#${hash}`;
}

async function createDashboardWindow() {
  const display = screen.getPrimaryDisplay();
  const work = display.workArea;
  dashboardWindow = new BrowserWindow({
    x: work.x + Math.max(0, Math.floor((work.width - 980) / 2)),
    y: work.y + Math.max(0, Math.floor((work.height - 680) / 2)),
    width: Math.min(980, work.width),
    height: Math.min(680, work.height),
    minWidth: 720,
    minHeight: 520,
    show: false,
    backgroundColor: '#090b10',
    title: `Biobase Client ${app.getVersion()}`,
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false },
  });
  await dashboardWindow.loadURL(rendererUrl('/'));
  applySingleVirtualDesktopPolicy(dashboardWindow);
  dashboardWindow.show();
  overlay.recordMainHeartbeat();
  dashboardWindow.on('closed', () => {
    dashboardWindow = null;
    overlay.closeOnMainWindowClosed();
  });
}

app.whenReady().then(async () => {
  overlay.registerGlobalSafetyShortcuts();
  setupTray();

  ipcMain.handle('biobase:show-overlay', () => overlay.showOverlay());
  ipcMain.handle('biobase:hide-overlay', () => overlay.hideOverlay());
  ipcMain.handle('biobase:toggle-overlay', () => overlay.toggleOverlay());
  ipcMain.handle('biobase:is-overlay-visible', () => overlay.isVisible());
  ipcMain.handle('biobase:is-overlay-disabled', () => isOverlayFeatureDisabled());
  ipcMain.handle('biobase:is-overlay-kill-switch', () => isOverlayKillSwitchActive());
  ipcMain.handle('biobase:main-heartbeat', () => {
    overlay.recordMainHeartbeat();
  });
  ipcMain.handle('biobase:scan-demos', scanLocalDemos);
  ipcMain.handle('biobase:select-demo', selectDemoFile);
  ipcMain.handle('biobase:import-demo', (_evt, filePath: string) => importDemo(filePath));
  ipcMain.handle('biobase:parse-demo', async (_evt, filePath: string) => {
    playbackState.demoPath = filePath;
    playbackState.offsetSec = 0;
    playbackState.startedAtMs = Date.now();
    playbackState.playing = false;
    return parseDemo(filePath);
  });
  ipcMain.handle('biobase:get-playback', () => ({ ...playbackState, currentTimeSec: currentTimeSec() }));
  ipcMain.handle('biobase:set-playback', (_evt, patch: Partial<typeof playbackState> & { currentTimeSec?: number }) => {
    if (typeof patch.currentTimeSec === 'number') playbackState.offsetSec = patch.currentTimeSec;
    if (typeof patch.playing === 'boolean') playbackState.playing = patch.playing;
    if (typeof patch.demoPath === 'string') playbackState.demoPath = patch.demoPath;
    playbackState.startedAtMs = Date.now();
    return { ...playbackState, currentTimeSec: currentTimeSec() };
  });
  ipcMain.handle('biobase:get-settings', async () => publicSettings(await getSettings()));
  ipcMain.handle('biobase:save-settings', async (_evt, patch: unknown) => {
    const next = publicSettings(await saveSettings(patch as Partial<ClientSettings>));
    setMovementTracking(next.trackedPlayerName ?? '', next.trackedSteamId ?? '');
    startMovementPolling();
    startLivePolling();
    void sendPresenceOnce();
    return next;
  });
  ipcMain.handle('biobase:pair-device', async (_evt, input: unknown) => {
    const result = await pairDevice(input as { pairingCode: string });
    if (result.ok) {
      startRemoteWatchdog(result.settings);
    }
    return { ...result, settings: publicSettings(result.settings) };
  });
  ipcMain.handle('biobase:get-upload-queue', getUploadQueue);
  ipcMain.handle('biobase:sync-upload-queue', syncUploadQueue);
  ipcMain.handle('biobase:upload-parsed-summary', (_evt, parsed: unknown) => uploadParsedSummary(parsed as never));
  ipcMain.handle('biobase:get-live-status', async () => getCachedLiveStatus());
  ipcMain.handle('biobase:reset-settings', async () => {
    const next = publicSettings(await resetSettings());
    setMovementTracking(next.trackedPlayerName ?? '', next.trackedSteamId ?? '');
    startLivePolling();
    startMovementPolling();
    await fetchLiveStatus();
    await fetchLiveMovement();
    return next;
  });
  ipcMain.handle('biobase:refresh-live-status', async () => fetchLiveStatus());
  ipcMain.handle('biobase:start-live-polling', async () => {
    startLivePolling();
    return getCachedLiveStatus();
  });
  ipcMain.handle('biobase:stop-live-polling', () => {
    stopLivePolling();
  });
  ipcMain.handle('biobase:get-live-movement', async () => getCachedLiveMovement());
  ipcMain.handle('biobase:refresh-live-movement', async () => {
    const settings = await getSettings();
    setMovementTracking(settings.trackedPlayerName ?? '', settings.trackedSteamId ?? '');
    return fetchLiveMovement();
  });
  ipcMain.handle('biobase:start-movement-polling', async () => {
    const settings = await getSettings();
    setMovementTracking(settings.trackedPlayerName ?? '', settings.trackedSteamId ?? '');
    startMovementPolling();
    return getCachedLiveMovement();
  });
  ipcMain.handle('biobase:stop-movement-polling', () => {
    stopMovementPolling();
  });
  ipcMain.handle('biobase:get-app-version', () => app.getVersion());
  ipcMain.handle('biobase:get-platform', () => process.platform);
  ipcMain.handle('biobase:get-update-status', () => getUpdateStatus());
  ipcMain.handle('biobase:check-for-updates', () => checkForUpdates());
  ipcMain.handle('biobase:download-update', () => downloadUpdate());
  ipcMain.handle('biobase:install-update', () => {
    installUpdate();
  });
  ipcMain.handle('biobase:open-manual-install', () => {
    openManualInstallPage();
  });
  ipcMain.handle('biobase:open-manual-install-mac', () => {
    openManualInstallMacPage();
  });
  ipcMain.handle('biobase:trigger-update', () => triggerAppUpdate());
  ipcMain.handle('biobase:create-companion-link', () => createCompanionLink());
  ipcMain.handle('biobase:connect-cs2', async (_evt, input?: { host?: string; port?: number }) =>
    connectToCs2Server(input?.host, input?.port));
  ipcMain.handle('biobase:is-cs2-running', () => isCs2Running());
  ipcMain.handle('biobase:copy-connect-command', (_evt, input?: { host?: string; port?: number }) =>
    copyConnectCommand(input?.host, input?.port));
  ipcMain.handle('biobase:create-cs2-shortcut', (_evt, input?: { host?: string; port?: number }) =>
    createCs2DesktopShortcut(input?.host, input?.port));
  ipcMain.handle('biobase:release-mouse', () => releaseMouseCapture());
  configureUpdateFeed();
  setupAutoUpdater();
  const settings = await getSettings();
  setOverlayUserOptedIn(Boolean(settings.overlayHudConfirmed));
  setMovementTracking(settings.trackedPlayerName ?? '', settings.trackedSteamId ?? '');
  startRemoteWatchdog(settings);
  startRemoteCommandPolling({
    closeOverlay: () => overlay.hideOverlay(),
    quitApp: () => {
      app.quit();
    },
  });
  startPresencePolling();
  await createDashboardWindow();
  await fetchLiveStatus();
  await fetchLiveMovement();
  startLivePolling();
  startMovementPolling();
  unpinAppFromAllVirtualDesktopsOnStartup();
  if (process.platform === 'win32') {
    void checkForUpdates().catch((error: unknown) => {
      console.error('[biobase-updater] startup check failed', error);
    });
  }
});

app.on('activate', () => {
  if (process.platform === 'darwin' && !dashboardWindow) {
    void createDashboardWindow();
  }
});

app.on('before-quit', () => {
  overlay.hideOverlay();
});

app.on('will-quit', () => {
  overlay.unregisterGlobalSafetyShortcuts();
  tray?.destroy();
  tray = null;
});

app.on('window-all-closed', () => {
  overlay.hideOverlay();
  if (process.platform !== 'darwin') app.quit();
});

process.on('exit', () => {
  overlay.unregisterGlobalSafetyShortcuts();
});
