export interface DeviceCredentials {
  deviceId?: string;
  deviceToken?: string;
}

export function sanitizeDeviceName(raw: string): string {
  const cleaned = raw
    .normalize('NFKD')
    .replace(/[^a-zA-Z0-9 ._-]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80);
  return cleaned || 'Biobase Client';
}

export function normalizeApiBaseUrl(raw: string): string {
  const value = raw.trim().replace(/\/$/, '');
  if (!value) return '';
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol)) throw new Error('invalid_protocol');
    return url.toString().replace(/\/$/, '');
  } catch {
    throw new Error('invalid_api_base_url');
  }
}

export function buildApiUrl(apiBaseUrl: string, endpoint: string): string {
  const base = normalizeApiBaseUrl(apiBaseUrl);
  if (!base) throw new Error('missing_api_base_url');
  return `${base}${endpoint.startsWith('/') ? endpoint : `/${endpoint}`}`;
}

export function createAuthHeaders(credentials: DeviceCredentials): Record<string, string> {
  const headers: Record<string, string> = {};
  if (credentials.deviceId && credentials.deviceToken) {
    headers['X-Biobase-Device-Id'] = credentials.deviceId;
    headers['X-Biobase-Device-Token'] = credentials.deviceToken;
  }
  return headers;
}

export function normalizePairingCode(raw: string): string {
  return raw.trim().replace(/\s+/g, '').toUpperCase();
}
