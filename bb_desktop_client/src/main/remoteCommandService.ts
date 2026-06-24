import electron from 'electron';
const { app } = electron;
import os from 'node:os';
import { getSettings } from './uploadService.js';
import { buildApiUrl, createAuthHeaders } from '../shared/apiClient.js';
import { checkForUpdates, downloadUpdate, getUpdateStatus, installUpdate } from './updateService.js';

const LOG_PREFIX = '[biobase-remote]';
const POLL_INTERVAL_MS = 30_000;

export type RemoteCommand = 'force_update' | 'kill_app' | 'close_overlay';

export interface RemoteCommandHandlers {
  closeOverlay: () => void;
  quitApp: () => void;
}

let pollTimer: ReturnType<typeof setInterval> | null = null;
let pollInFlight = false;

function log(message: string, detail?: unknown) {
  if (detail === undefined) {
    console.log(`${LOG_PREFIX} ${message}`);
    return;
  }
  console.log(`${LOG_PREFIX} ${message}`, detail);
}

function pollHeaders(): Record<string, string> {
  return {
    'X-Biobase-App-Version': app.getVersion(),
    'X-Biobase-Hostname': os.hostname(),
  };
}

async function sleep(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForUpdateReady(timeoutMs = 120_000): Promise<boolean> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const status = getUpdateStatus();
    if (status.state === 'ready') return true;
    if (status.state === 'not-available') return false;
    if (status.state === 'error') return false;
    await sleep(1500);
  }
  return getUpdateStatus().state === 'ready';
}

async function executeForceUpdate(): Promise<void> {
  log('force_update → check + download + install');
  await checkForUpdates();
  const status = getUpdateStatus();
  if (status.state === 'not-available') {
    log('force_update: already on latest build');
    return;
  }
  if (status.state !== 'ready') {
    await downloadUpdate();
  }
  const ready = await waitForUpdateReady();
  if (ready) {
    installUpdate();
    return;
  }
  log('force_update: update not ready after wait');
}

async function executeCommand(command: RemoteCommand, handlers: RemoteCommandHandlers): Promise<void> {
  switch (command) {
    case 'close_overlay':
      log('close_overlay');
      handlers.closeOverlay();
      return;
    case 'kill_app':
      log('kill_app (main scope — graceful quit)');
      handlers.closeOverlay();
      handlers.quitApp();
      return;
    case 'force_update':
      await executeForceUpdate();
      return;
    default:
      log(`ignored unknown command: ${command}`);
  }
}

async function pollRemoteCommands(handlers: RemoteCommandHandlers): Promise<void> {
  try {
    const settings = await getSettings();
    if (!settings.deviceId || !settings.deviceToken) {
      return;
    }
    const url = buildApiUrl(settings.apiBaseUrl, '/api/client/device/commands?scope=main');
    const shareStats = settings.shareStatsOnServer !== false;
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        ...createAuthHeaders(settings),
        ...pollHeaders(),
        'X-Biobase-Share-Stats': shareStats ? '1' : '0',
        'X-Biobase-Tracked-Player': settings.trackedPlayerName?.trim() ?? '',
      },
    });
    if (!response.ok) {
      log(`poll failed http_${response.status}`);
      return;
    }
    const payload = (await response.json()) as { commands?: Array<{ command?: string }> };
    const commands = payload.commands ?? [];
    for (const entry of commands) {
      const command = entry.command as RemoteCommand | undefined;
      if (!command) continue;
      void executeCommand(command, handlers).catch((error: unknown) => {
        log(`command ${command} failed`, error);
      });
    }
  } catch (error) {
    log('poll error', error);
  }
}

export function startRemoteCommandPolling(handlers: RemoteCommandHandlers): void {
  if (pollTimer) return;
  const tick = () => {
    if (pollInFlight) {
      log('poll skipped — previous request still in flight');
      return;
    }
    pollInFlight = true;
    void pollRemoteCommands(handlers).finally(() => {
      pollInFlight = false;
    });
  };
  tick();
  pollTimer = setInterval(tick, POLL_INTERVAL_MS);
  log(`polling every ${POLL_INTERVAL_MS / 1000}s (scope=main, interval survives overlay)`);
}

export function stopRemoteCommandPolling(): void {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}
