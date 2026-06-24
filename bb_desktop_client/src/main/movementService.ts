import { adminApiPath, fetchAdminJson } from './adminHttp.js';
import type { LiveMovementStatus } from '../shared/liveTypes.js';
import { enrichLiveSample } from '../shared/liveMovementMetrics.js';

let cached: LiveMovementStatus | null = null;
let pollTimer: ReturnType<typeof setInterval> | null = null;
let fetchInFlight: Promise<LiveMovementStatus> | null = null;
let trackedPlayer = '';
let trackedSteamId = '';

export function getCachedLiveMovement(): LiveMovementStatus | null {
  return cached;
}

function trackingQuery(): string {
  const params = new URLSearchParams();
  if (trackedSteamId.trim()) params.set('steamid', trackedSteamId.trim());
  else if (trackedPlayer.trim()) params.set('player', trackedPlayer.trim());
  const query = params.toString();
  return query ? `?${query}` : '';
}

export function setMovementTracking(playerName: string, steamid = ''): void {
  trackedPlayer = playerName.trim();
  trackedSteamId = steamid.trim();
}

function offlineMovement(error: string, detail?: string): LiveMovementStatus {
  return {
    ok: false,
    error,
    detail,
    samples: [],
    tracked: null,
    polledAt: new Date().toISOString(),
  };
}

async function fetchLiveMovementOnce(): Promise<LiveMovementStatus> {
  try {
    const { status, text } = await fetchAdminJson(`${adminApiPath('/api/client/live/movement')}${trackingQuery()}`);
    let data: LiveMovementStatus;
    try {
      data = JSON.parse(text) as LiveMovementStatus;
    } catch {
      cached = offlineMovement('invalid_api_response', text.slice(0, 160));
      return cached;
    }
    const tracked = data.tracked ? enrichLiveSample(data.tracked) : null;
    const samples = (data.samples ?? []).map((sample) => enrichLiveSample(sample));
    const hasPayload = status >= 200 && status < 500;
    cached = {
      ...data,
      ok: hasPayload && Boolean(data.ok),
      error: data.error ?? (hasPayload ? null : `http_${status}`),
      samples,
      tracked,
    };
    return cached;
  } catch (error) {
    cached = offlineMovement('network_error', error instanceof Error ? error.message : String(error));
    return cached;
  }
}

export async function fetchLiveMovement(): Promise<LiveMovementStatus> {
  if (fetchInFlight) return fetchInFlight;
  fetchInFlight = fetchLiveMovementOnce().finally(() => {
    fetchInFlight = null;
  });
  return fetchInFlight;
}

export function startMovementPolling(intervalMs = 500): void {
  stopMovementPolling();
  const tick = () => {
    void fetchLiveMovement();
  };
  pollTimer = setInterval(tick, intervalMs);
}

export function stopMovementPolling(): void {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}
