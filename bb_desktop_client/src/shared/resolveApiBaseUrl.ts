import { DEFAULT_API_BASE_URL } from './biobaseEndpoints.js';

export function resolveLiveApiBaseUrl(_settingsUrl?: string): string {
  return DEFAULT_API_BASE_URL;
}
