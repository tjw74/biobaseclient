import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('biobaseDesktop', {
  showOverlay: () => ipcRenderer.invoke('biobase:show-overlay'),
  hideOverlay: () => ipcRenderer.invoke('biobase:hide-overlay'),
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
});
