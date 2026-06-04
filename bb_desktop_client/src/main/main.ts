import { app, BrowserWindow, ipcMain, screen } from 'electron';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { importDemo, parseDemo, scanLocalDemos, selectDemoFile } from './demoService.js';
import { getSettings, getUploadQueue, saveSettings, syncUploadQueue, uploadParsedSummary } from './uploadService.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let dashboardWindow: BrowserWindow | null = null;
let overlayWindow: BrowserWindow | null = null;

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

function rendererUrl(route: string) {
  const devUrl = process.env.VITE_DEV_SERVER_URL;
  if (devUrl) return `${devUrl}${route}`;
  return `file://${path.join(__dirname, '../renderer/index.html')}#${route}`;
}

async function createDashboardWindow() {
  dashboardWindow = new BrowserWindow({
    width: 1240,
    height: 800,
    minWidth: 980,
    minHeight: 640,
    backgroundColor: '#090b10',
    title: 'Biobase Client',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  await dashboardWindow.loadURL(rendererUrl('/'));
}

async function createOverlayWindow() {
  if (overlayWindow) {
    overlayWindow.focus();
    return;
  }
  const display = screen.getPrimaryDisplay();
  overlayWindow = new BrowserWindow({
    x: display.workArea.x,
    y: display.workArea.y,
    width: display.workArea.width,
    height: display.workArea.height,
    frame: false,
    transparent: true,
    resizable: false,
    hasShadow: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    title: 'Biobase HUD Overlay',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  overlayWindow.setAlwaysOnTop(true, 'screen-saver');
  overlayWindow.setIgnoreMouseEvents(true, { forward: true });
  overlayWindow.on('closed', () => {
    overlayWindow = null;
  });
  await overlayWindow.loadURL(rendererUrl('/overlay'));
}

app.whenReady().then(async () => {
  ipcMain.handle('biobase:show-overlay', createOverlayWindow);
  ipcMain.handle('biobase:hide-overlay', () => overlayWindow?.close());
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
  ipcMain.handle('biobase:get-settings', getSettings);
  ipcMain.handle('biobase:save-settings', (_evt, patch: unknown) => saveSettings(patch as Record<string, string>));
  ipcMain.handle('biobase:get-upload-queue', getUploadQueue);
  ipcMain.handle('biobase:sync-upload-queue', syncUploadQueue);
  ipcMain.handle('biobase:upload-parsed-summary', (_evt, parsed: unknown) => uploadParsedSummary(parsed as never));
  await createDashboardWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
