import crypto from 'node:crypto';
import electron from 'electron';
const { app } = electron;
import os from 'node:os';
import { buildApiUrl } from '../shared/apiClient.js';
import { getSettings, saveSettings } from './uploadService.js';

const LOG_PREFIX = '[biobase-presence]';
const POLL_INTERVAL_MS = 30_000;

let pollTimer: ReturnType<typeof setInterval> | null = null;
let sendInFlight = false;

function log(message: string, detail?: unknown) {
  if (detail === undefined) {
    console.log(`${LOG_PREFIX} ${message}`);
    return;
  }
  console.log(`${LOG_PREFIX} ${message}`, detail);
}

async function ensureSessionId(): Promise<string> {
  const settings = await getSettings();
  if (settings.presenceSessionId?.trim()) {
    return settings.presenceSessionId.trim();
  }
  const sessionId = `sess_${crypto.randomUUID().replace(/-/g, '').slice(0, 16)}`;
  await saveSettings({ presenceSessionId: sessionId });
  return sessionId;
}

export async function sendPresenceOnce(): Promise<void> {
  if (sendInFlight) return;
  sendInFlight = true;
  try {
    const settings = await getSettings();
    const sessionId = await ensureSessionId();
    const shareStats = settings.shareStatsOnServer !== false;
    const url = buildApiUrl(settings.apiBaseUrl, '/api/client/live/presence');
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        sessionId,
        deviceName: settings.deviceName,
        playerName: settings.trackedPlayerName?.trim() ?? '',
        shareStats,
        appVersion: app.getVersion(),
        hostname: os.hostname(),
      }),
    });
    if (!response.ok) {
      log(`presence http_${response.status}`);
    }
  } catch (error) {
    log('presence error', error);
  } finally {
    sendInFlight = false;
  }
}

export function startPresencePolling(): void {
  stopPresencePolling();
  const tick = () => {
    void sendPresenceOnce();
  };
  tick();
  pollTimer = setInterval(tick, POLL_INTERVAL_MS);
  log(`polling every ${POLL_INTERVAL_MS / 1000}s`);
}

export function stopPresencePolling(): void {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}
