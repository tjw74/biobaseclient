import electron from 'electron';
import { createRequire } from 'node:module';
const { app, BrowserWindow, dialog, session, shell } = electron;
import { DEFAULT_UPDATE_FEED_URL, MANUAL_INSTALL_MAC_URL, MANUAL_INSTALL_URL } from '../shared/biobaseEndpoints.js';

import type { UpdateStatus } from '../shared/updateTypes.js';

const require = createRequire(import.meta.url);
const { autoUpdater } = require('electron-updater') as typeof import('electron-updater');

// electron-updater defaults to an isolated "electron-updater" session partition.
// Route through defaultSession — same network path as adminHttp (works on user PCs).
const electronHttpExecutor = require('electron-updater/out/electronHttpExecutor') as {
  getNetSession: () => Electron.Session;
};
electronHttpExecutor.getNetSession = () => session.defaultSession;

const LOG_PREFIX = '[biobase-updater]';
const CHECK_TIMEOUT_MS = 45_000;

let feedUrl = DEFAULT_UPDATE_FEED_URL;
let restartPromptOpen = false;

let status: UpdateStatus = {
  currentVersion: app.getVersion(),
  state: 'idle',
};

function logInfo(message: string, detail?: unknown) {
  if (detail === undefined) {
    console.log(`${LOG_PREFIX} ${message}`);
    return;
  }
  console.log(`${LOG_PREFIX} ${message}`, detail);
}

function logError(message: string, detail?: unknown) {
  if (detail === undefined) {
    console.error(`${LOG_PREFIX} ${message}`);
    return;
  }
  console.error(`${LOG_PREFIX} ${message}`, detail);
}

function feedBaseUrl(url: string = feedUrl): string {
  return url.endsWith('/') ? url : `${url}/`;
}

function broadcastStatus() {
  for (const window of BrowserWindow.getAllWindows()) {
    window.webContents.send('biobase:update-status', status);
  }
}

function setStatus(next: Partial<UpdateStatus>) {
  status = { ...status, currentVersion: app.getVersion(), ...next };
  logInfo(`status → ${status.state}${status.latestVersion ? ` (latest ${status.latestVersion})` : ''}${status.message ? `: ${status.message}` : ''}`);
  broadcastStatus();
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_resolve, reject) => {
      setTimeout(() => reject(new Error(`${label} timed out after ${Math.round(timeoutMs / 1000)}s`)), timeoutMs);
    }),
  ]);
}

function formatError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function applyCheckResult(result: { isUpdateAvailable: boolean; updateInfo: { version: string } }) {
  if (result.isUpdateAvailable) {
    setStatus({
      state: 'downloading',
      latestVersion: result.updateInfo.version,
      message: `Downloading v${result.updateInfo.version}…`,
      progress: 0,
    });
    return;
  }
  setStatus({
    state: 'not-available',
    latestVersion: result.updateInfo.version,
    message: 'Already on the latest build.',
  });
}

async function fetchLatestVersionViaSession(): Promise<string> {
  const url = `${feedBaseUrl()}latest.yml`;
  logInfo(`session.fetch ${url}`);
  const response = await session.defaultSession.fetch(url, {
    method: 'GET',
    headers: { Accept: 'text/yaml, text/plain, */*' },
  });
  if (!response.ok) {
    throw new Error(`Update feed HTTP ${response.status}`);
  }
  const text = await response.text();
  const versionMatch = text.match(/^version:\s*([^\s]+)/m);
  if (!versionMatch?.[1]) {
    throw new Error('Update feed missing version field');
  }
  return versionMatch[1];
}

function parseVersionParts(version: string): number[] {
  return version.split('.').map((part) => Number.parseInt(part, 10) || 0);
}

function isNewerVersion(latest: string, current: string): boolean {
  const latestParts = parseVersionParts(latest);
  const currentParts = parseVersionParts(current);
  const len = Math.max(latestParts.length, currentParts.length);
  for (let i = 0; i < len; i += 1) {
    const diff = (latestParts[i] ?? 0) - (currentParts[i] ?? 0);
    if (diff !== 0) return diff > 0;
  }
  return false;
}

async function fallbackCheckViaSessionFetch(cause?: unknown): Promise<void> {
  logInfo('trying session.fetch fallback');
  try {
    const latestVersion = await fetchLatestVersionViaSession();
    const currentVersion = app.getVersion();
    logInfo(`fallback compare current=${currentVersion} latest=${latestVersion}`);
    if (isNewerVersion(latestVersion, currentVersion)) {
      setStatus({
        state: 'available',
        latestVersion,
        message: 'Update found — downloading automatically…',
        progress: 0,
      });
      void downloadUpdate().catch((error: unknown) => {
        logError('fallback auto-download failed', error);
      });
      return;
    }
    setStatus({
      state: 'not-available',
      latestVersion,
      message: 'Already on the latest build.',
    });
  } catch (fallbackError) {
    const causeMsg = cause ? formatError(cause) : '';
    const fallbackMsg = formatError(fallbackError);
    const message = causeMsg
      ? `${causeMsg} Fallback check failed: ${fallbackMsg}.`
      : `Could not reach update feed: ${fallbackMsg}.`;
    setStatus({ state: 'error', message });
  }
}

async function ensureAutoUpdaterHasUpdate(): Promise<void> {
  logInfo('ensureAutoUpdaterHasUpdate → re-check before download');
  const result = await withTimeout(autoUpdater.checkForUpdates(), CHECK_TIMEOUT_MS, 'Pre-download check');
  if (!result?.isUpdateAvailable) {
    throw new Error('No pending update for in-app download. Use “Download in browser”.');
  }
}

async function promptRestartAfterDownload(version: string): Promise<void> {
  if (restartPromptOpen) return;
  restartPromptOpen = true;
  try {
    const parent = BrowserWindow.getFocusedWindow() ?? BrowserWindow.getAllWindows()[0] ?? undefined;
    const result = await dialog.showMessageBox(parent, {
      type: 'info',
      title: 'Update ready',
      message: `Biobase Client v${version} has been downloaded.`,
      detail: 'Restart now to apply the update, or choose Later to finish what you are doing.',
      buttons: ['Restart now', 'Later'],
      defaultId: 0,
      cancelId: 1,
      noLink: true,
    });
    if (result.response === 0) {
      installUpdate();
    }
  } finally {
    restartPromptOpen = false;
  }
}

export function getUpdateStatus(): UpdateStatus {
  return { ...status, currentVersion: app.getVersion() };
}

export function setupAutoUpdater(): void {
  autoUpdater.logger = {
    info: (message?: unknown) => logInfo(String(message ?? '')),
    warn: (message?: unknown) => console.warn(`${LOG_PREFIX} ${String(message ?? '')}`),
    error: (message?: unknown) => logError(String(message ?? '')),
  };
  autoUpdater.autoDownload = true;
  autoUpdater.disableWebInstaller = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.allowDowngrade = false;

  autoUpdater.on('checking-for-update', () => {
    setStatus({ state: 'checking', message: 'Checking for updates…' });
  });
  autoUpdater.on('update-available', (info) => {
    setStatus({
      state: 'downloading',
      latestVersion: info.version,
      message: `Downloading v${info.version}…`,
      progress: 0,
    });
  });
  autoUpdater.on('update-not-available', (info) => {
    setStatus({ state: 'not-available', latestVersion: info.version, message: 'Already on the latest build.' });
  });
  autoUpdater.on('error', (error) => {
    logError('autoUpdater error event', error);
    // During check we recover via session.fetch fallback — don't clobber that path.
    if (status.state === 'checking') return;
    if (status.state === 'downloading' || status.state === 'available') {
      setStatus({
        state: 'error',
        message: `${error.message} Use “Download in browser” if this keeps failing.`,
      });
    }
  });
  autoUpdater.on('download-progress', (progress) => {
    setStatus({ state: 'downloading', progress: progress.percent, message: undefined });
  });
  autoUpdater.on('update-downloaded', (info) => {
    setStatus({
      state: 'ready',
      latestVersion: info.version,
      progress: 100,
      message: 'Update downloaded — restart to apply.',
    });
    void promptRestartAfterDownload(info.version);
  });
}

export async function checkForUpdates(): Promise<UpdateStatus> {
  logInfo('checkForUpdates');
  setStatus({ state: 'checking', message: 'Checking for updates…' });
  try {
    const result = await withTimeout(autoUpdater.checkForUpdates(), CHECK_TIMEOUT_MS, 'Update check');
    logInfo('checkForUpdates resolved', result);
    if (result) {
      applyCheckResult(result);
    } else if (status.state === 'checking') {
      await fallbackCheckViaSessionFetch();
    }
  } catch (error) {
    logError('checkForUpdates failed', error);
    await fallbackCheckViaSessionFetch(error);
  }
  return getUpdateStatus();
}

export async function downloadUpdate(): Promise<UpdateStatus> {
  logInfo('downloadUpdate');
  try {
    setStatus({ state: 'downloading', progress: 0, message: 'Downloading update…' });
    await ensureAutoUpdaterHasUpdate();
    await withTimeout(autoUpdater.downloadUpdate(), CHECK_TIMEOUT_MS * 4, 'Update download');
  } catch (error) {
    logError('downloadUpdate failed', error);
    setStatus({
      state: 'error',
      message: `${formatError(error)} Use “Download in browser” if this keeps failing.`,
    });
  }
  return getUpdateStatus();
}

export function installUpdate(): void {
  logInfo('installUpdate → quitAndInstall');
  autoUpdater.quitAndInstall(true, true);
}

export function openManualInstallPage(): void {
  logInfo(`openManualInstallPage → ${MANUAL_INSTALL_URL}`);
  void shell.openExternal(MANUAL_INSTALL_URL);
}

export function openManualInstallMacPage(): void {
  logInfo(`openManualInstallMacPage → ${MANUAL_INSTALL_MAC_URL}`);
  void shell.openExternal(MANUAL_INSTALL_MAC_URL);
}

export async function triggerAppUpdate(): Promise<UpdateStatus> {
  if (process.platform === 'darwin') {
    openManualInstallMacPage();
    return {
      ...getUpdateStatus(),
      message: 'Opening Mac download in your browser…',
    };
  }
  const current = getUpdateStatus();
  if (current.state === 'ready') {
    return current;
  }
  return checkForUpdates();
}

export function configureUpdateFeed(url: string = DEFAULT_UPDATE_FEED_URL): void {
  feedUrl = url;
  autoUpdater.setFeedURL({ provider: 'generic', url: feedBaseUrl(url) });
  logInfo(`feed configured ${feedBaseUrl(url)} (defaultSession)`);
}
