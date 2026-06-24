import { buildApiUrl } from '../shared/apiClient.js';
import { getSettings } from './uploadService.js';

export interface CompanionLinkResult {
  ok: boolean;
  code?: string;
  url?: string;
  playerName?: string;
  expiresAt?: string;
  error?: string;
}

export async function createCompanionLink(): Promise<CompanionLinkResult> {
  try {
    const settings = await getSettings();
    const playerName = settings.trackedPlayerName?.trim() ?? '';
    const response = await fetch(buildApiUrl(settings.apiBaseUrl, '/api/client/companion/link'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        playerName,
        steamid: settings.trackedSteamId ?? '',
        deviceName: settings.deviceName,
      }),
    });
    if (!response.ok) {
      return { ok: false, error: `http_${response.status}` };
    }
    const payload = (await response.json()) as {
      code?: string;
      url?: string;
      playerName?: string;
      expiresAt?: string;
    };
    if (!payload.code || !payload.url) {
      return { ok: false, error: 'invalid_response' };
    }
    return {
      ok: true,
      code: payload.code,
      url: payload.url,
      playerName: payload.playerName,
      expiresAt: payload.expiresAt,
    };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}
