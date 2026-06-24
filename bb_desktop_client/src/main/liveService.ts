import { adminApiPath, fetchAdminJson } from './adminHttp.js';
import { DEFAULT_CONNECT } from '../shared/biobaseEndpoints.js';
import type { LiveServerStatus } from '../shared/liveTypes.js';

let cached: LiveServerStatus | null = null;
let pollTimer: ReturnType<typeof setInterval> | null = null;
let fetchInFlight: Promise<LiveServerStatus> | null = null;

export function getCachedLiveStatus(): LiveServerStatus | null {
  return cached;
}

function offlineStatus(error: string, detail?: string): LiveServerStatus {
  return {
    ok: false,
    error,
    detail,
    connect: DEFAULT_CONNECT,
    polledAt: new Date().toISOString(),
  };
}

async function fetchLiveStatusOnce(): Promise<LiveServerStatus> {
  try {
    const { status, text } = await fetchAdminJson(adminApiPath('/api/client/live/status'));
    let data: LiveServerStatus;
    try {
      data = JSON.parse(text) as LiveServerStatus;
    } catch {
      cached = offlineStatus('invalid_api_response', text.slice(0, 160));
      return cached;
    }
    cached = { ...data, ok: status >= 200 && status < 300 && Boolean(data.ok) };
    if (!cached.ok && !cached.error) cached.error = 'server_unreachable';
    return cached;
  } catch (error) {
    cached = offlineStatus('network_error', error instanceof Error ? error.message : String(error));
    return cached;
  }
}

export async function fetchLiveStatus(): Promise<LiveServerStatus> {
  if (fetchInFlight) return fetchInFlight;
  fetchInFlight = fetchLiveStatusOnce().finally(() => {
    fetchInFlight = null;
  });
  return fetchInFlight;
}

export function startLivePolling(intervalMs = 2000): void {
  stopLivePolling();
  const tick = () => {
    void fetchLiveStatus();
  };
  pollTimer = setInterval(tick, intervalMs);
}

export function stopLivePolling(): void {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}
