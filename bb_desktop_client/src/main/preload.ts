import type { IpcRenderer } from 'electron';
import type { UpdateStatus } from '../shared/updateTypes.js';

// Sandboxed preload scripts cannot use ESM import(); require() is required (Electron ESM docs).
const { contextBridge, ipcRenderer } = require('electron') as {
  contextBridge: typeof import('electron').contextBridge;
  ipcRenderer: IpcRenderer;
};

contextBridge.exposeInMainWorld('biobaseDesktop', {
  showOverlay: () => ipcRenderer.invoke('biobase:show-overlay'),
  hideOverlay: () => ipcRenderer.invoke('biobase:hide-overlay'),
  toggleOverlay: () => ipcRenderer.invoke('biobase:toggle-overlay'),
  isOverlayVisible: () => ipcRenderer.invoke('biobase:is-overlay-visible') as Promise<boolean>,
  isOverlayDisabled: () => ipcRenderer.invoke('biobase:is-overlay-disabled') as Promise<boolean>,
  isOverlayKillSwitch: () => ipcRenderer.invoke('biobase:is-overlay-kill-switch') as Promise<boolean>,
  sendMainHeartbeat: () => ipcRenderer.invoke('biobase:main-heartbeat'),
  scanDemos: () => ipcRenderer.invoke('biobase:scan-demos'),
  selectDemo: () => ipcRenderer.invoke('biobase:select-demo'),
  importDemo: (filePath: string) => ipcRenderer.invoke('biobase:import-demo', filePath),
  parseDemo: (filePath: string) => ipcRenderer.invoke('biobase:parse-demo', filePath),
  getPlayback: () => ipcRenderer.invoke('biobase:get-playback'),
  setPlayback: (patch: unknown) => ipcRenderer.invoke('biobase:set-playback', patch),
  getSettings: () => ipcRenderer.invoke('biobase:get-settings'),
  saveSettings: (patch: unknown) => ipcRenderer.invoke('biobase:save-settings', patch),
  pairDevice: (input: unknown) => ipcRenderer.invoke('biobase:pair-device', input),
  getUploadQueue: () => ipcRenderer.invoke('biobase:get-upload-queue'),
  syncUploadQueue: () => ipcRenderer.invoke('biobase:sync-upload-queue'),
  uploadParsedSummary: (parsed: unknown) => ipcRenderer.invoke('biobase:upload-parsed-summary', parsed),
  resetSettings: () => ipcRenderer.invoke('biobase:reset-settings'),
  getLiveStatus: () => ipcRenderer.invoke('biobase:get-live-status'),
  refreshLiveStatus: () => ipcRenderer.invoke('biobase:refresh-live-status'),
  startLivePolling: () => ipcRenderer.invoke('biobase:start-live-polling'),
  stopLivePolling: () => ipcRenderer.invoke('biobase:stop-live-polling'),
  getLiveMovement: () => ipcRenderer.invoke('biobase:get-live-movement'),
  refreshLiveMovement: () => ipcRenderer.invoke('biobase:refresh-live-movement'),
  startMovementPolling: () => ipcRenderer.invoke('biobase:start-movement-polling'),
  stopMovementPolling: () => ipcRenderer.invoke('biobase:stop-movement-polling'),
  getAppVersion: () => ipcRenderer.invoke('biobase:get-app-version') as Promise<string>,
  getPlatform: () => ipcRenderer.invoke('biobase:get-platform') as Promise<NodeJS.Platform>,
  getUpdateStatus: () => ipcRenderer.invoke('biobase:get-update-status') as Promise<UpdateStatus>,
  checkForUpdates: () => ipcRenderer.invoke('biobase:check-for-updates') as Promise<UpdateStatus>,
  downloadUpdate: () => ipcRenderer.invoke('biobase:download-update') as Promise<UpdateStatus>,
  installUpdate: () => ipcRenderer.invoke('biobase:install-update') as Promise<void>,
  openManualInstall: () => ipcRenderer.invoke('biobase:open-manual-install') as Promise<void>,
  openManualInstallMac: () => ipcRenderer.invoke('biobase:open-manual-install-mac') as Promise<void>,
  triggerUpdate: () => ipcRenderer.invoke('biobase:trigger-update') as Promise<UpdateStatus>,
  connectCs2: (input?: { host?: string; port?: number }) =>
    ipcRenderer.invoke('biobase:connect-cs2', input) as Promise<
      { ok: true; url: string; host: string; port: number } | { ok: false; error: string }
    >,
  isCs2Running: () => ipcRenderer.invoke('biobase:is-cs2-running') as Promise<boolean>,
  copyConnectCommand: (input?: { host?: string; port?: number }) =>
    ipcRenderer.invoke('biobase:copy-connect-command', input) as Promise<
      { ok: true; text: string } | { ok: false; error: string }
    >,
  createCs2Shortcut: (input?: { host?: string; port?: number }) =>
    ipcRenderer.invoke('biobase:create-cs2-shortcut', input) as Promise<
      { ok: true; path: string } | { ok: false; error: string }
    >,
  createCompanionLink: () =>
    ipcRenderer.invoke('biobase:create-companion-link') as Promise<
      { ok: boolean; code?: string; url?: string; playerName?: string; expiresAt?: string; error?: string }
    >,
  releaseMouse: () =>
    ipcRenderer.invoke('biobase:release-mouse') as Promise<{ ok: true } | { ok: false; error: string }>,
  onUpdateStatus: (listener: (status: UpdateStatus) => void) => {
    const handler = (_event: unknown, status: UpdateStatus) => listener(status);
    ipcRenderer.on('biobase:update-status', handler);
    return () => ipcRenderer.removeListener('biobase:update-status', handler);
  },
});
