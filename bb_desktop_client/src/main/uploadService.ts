import electron from 'electron';
const { app, safeStorage } = electron;
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import type { ParsedDemoSummary, UploadQueueItem, ClientSettings, PairDeviceResult } from '../shared/types.js';
import { buildApiUrl, createAuthHeaders, normalizeApiBaseUrl, normalizePairingCode, sanitizeDeviceName } from '../shared/apiClient.js';
import { DEFAULT_API_BASE_URL } from '../shared/biobaseEndpoints.js';
import { resolveLiveApiBaseUrl } from '../shared/resolveApiBaseUrl.js';

const SETTINGS_FILE = 'settings.json';
const QUEUE_FILE = 'upload_queue.json';
type StoredClientSettings = Partial<ClientSettings> & { deviceTokenEncrypted?: string };

function dataPath(name: string) {
  return path.join(app.getPath('userData'), name);
}

function defaultSettings(): ClientSettings {
  return {
    apiBaseUrl: process.env.VITE_BIOBASE_API_URL ?? DEFAULT_API_BASE_URL,
    deviceName: sanitizeDeviceName(os.hostname()),
    serverName: process.env.VITE_BIOBASE_SERVER_NAME ?? 'Biobase CS2',
    shareStatsOnServer: true,
  };
}

async function readJson<T>(file: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await fs.readFile(dataPath(file), 'utf8')) as T;
  } catch {
    return fallback;
  }
}

async function writeJson(file: string, value: unknown): Promise<void> {
  await fs.mkdir(app.getPath('userData'), { recursive: true });
  await fs.writeFile(dataPath(file), JSON.stringify(value, null, 2));
}

function decryptStoredToken(saved: StoredClientSettings): string | undefined {
  if (saved.deviceToken) return saved.deviceToken;
  if (!saved.deviceTokenEncrypted) return undefined;
  try {
    if (!safeStorage.isEncryptionAvailable()) return undefined;
    return safeStorage.decryptString(Buffer.from(saved.deviceTokenEncrypted, 'base64'));
  } catch {
    return undefined;
  }
}

function settingsForStorage(settings: ClientSettings): StoredClientSettings {
  const stored: StoredClientSettings = { ...settings };
  if (settings.deviceToken) {
    if (safeStorage.isEncryptionAvailable()) {
      stored.deviceTokenEncrypted = safeStorage.encryptString(settings.deviceToken).toString('base64');
      delete stored.deviceToken;
    }
  }
  return stored;
}

function normalizeStoredApiUrl(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return DEFAULT_API_BASE_URL;
  try {
    const normalized = normalizeApiBaseUrl(trimmed);
    return normalized.endsWith('/admin') ? normalized : DEFAULT_API_BASE_URL;
  } catch {
    return DEFAULT_API_BASE_URL;
  }
}

export async function getSettings(): Promise<ClientSettings> {
  const saved = await readJson<StoredClientSettings>(SETTINGS_FILE, {});
  const deviceToken = decryptStoredToken(saved);
  const { deviceTokenEncrypted: _deviceTokenEncrypted, ...publicSaved } = saved;
  const merged = { ...defaultSettings(), ...publicSaved, ...(deviceToken ? { deviceToken } : {}) };
  merged.apiBaseUrl = resolveLiveApiBaseUrl(normalizeStoredApiUrl(merged.apiBaseUrl ?? ''));
  if (saved.apiBaseUrl !== merged.apiBaseUrl) {
    await writeJson(SETTINGS_FILE, settingsForStorage(merged));
  }
  return merged;
}

export async function saveSettings(patch: Partial<ClientSettings>): Promise<ClientSettings> {
  const next = { ...(await getSettings()), ...patch };
  next.apiBaseUrl = normalizeStoredApiUrl(next.apiBaseUrl ?? '');
  next.deviceName = sanitizeDeviceName(next.deviceName ?? os.hostname());
  next.serverName = (next.serverName ?? '').trim() || 'Biobase CS2';
  await writeJson(SETTINGS_FILE, settingsForStorage(next));
  return next;
}

export async function resetSettings(): Promise<ClientSettings> {
  const next = defaultSettings();
  await writeJson(SETTINGS_FILE, settingsForStorage(next));
  return next;
}

export async function getUploadQueue(): Promise<UploadQueueItem[]> {
  return readJson<UploadQueueItem[]>(QUEUE_FILE, []);
}

async function saveUploadQueue(items: UploadQueueItem[]): Promise<UploadQueueItem[]> {
  await writeJson(QUEUE_FILE, items);
  return items;
}

export async function enqueueParsedSummary(parsed: ParsedDemoSummary): Promise<UploadQueueItem> {
  const queue = await getUploadQueue();
  const now = new Date().toISOString();
  const existing = queue.find((item) => item.sha256 === parsed.sha256);
  if (existing) {
    existing.payload = parsed;
    existing.status = 'queued';
    existing.updatedAt = now;
    existing.lastError = undefined;
    await saveUploadQueue(queue);
    return existing;
  }
  const item: UploadQueueItem = {
    id: `demo_${parsed.sha256.slice(0, 16)}`,
    sha256: parsed.sha256,
    demoName: parsed.demoPath.split(/[\\/]/).pop() ?? 'demo.dem',
    status: 'queued',
    attempts: 0,
    createdAt: now,
    updatedAt: now,
    payload: parsed,
  };
  queue.unshift(item);
  await saveUploadQueue(queue.slice(0, 100));
  return item;
}

export async function syncUploadQueue(): Promise<UploadQueueItem[]> {
  const settings = await getSettings();
  const queue = await getUploadQueue();
  if (!settings.apiBaseUrl) {
    const next: UploadQueueItem[] = queue.map((item) => ({ ...item, status: item.status === 'uploaded' ? 'uploaded' : 'queued', lastError: 'missing_api_base_url' }));
    await saveUploadQueue(next);
    return next;
  }

  const next: UploadQueueItem[] = [];
  for (const item of queue) {
    if (item.status === 'uploaded') {
      next.push(item);
      continue;
    }
    const now = new Date().toISOString();
    const updated: UploadQueueItem = { ...item, status: 'uploading', attempts: item.attempts + 1, updatedAt: now };
    try {
      const response = await fetch(buildApiUrl(settings.apiBaseUrl, '/api/client/sessions'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...createAuthHeaders(settings) },
        body: JSON.stringify({
          kind: 'biobase-client-demo-summary',
          version: 1,
          deviceName: settings.deviceName,
          serverName: settings.serverName,
          uploadedAt: now,
          parsed: item.payload,
        }),
      });
      if (!response.ok) throw new Error(`http_${response.status}`);
      next.push({ ...updated, status: 'uploaded', lastError: undefined, uploadedAt: new Date().toISOString() });
    } catch (err) {
      next.push({ ...updated, status: 'failed', lastError: err instanceof Error ? err.message : String(err) });
    }
  }
  return saveUploadQueue(next);
}

export async function uploadParsedSummary(parsed: ParsedDemoSummary): Promise<{ item: UploadQueueItem; queue: UploadQueueItem[] }> {
  const item = await enqueueParsedSummary(parsed);
  const queue = await syncUploadQueue();
  return { item: queue.find((q) => q.id === item.id) ?? item, queue };
}


export async function pairDevice(input: { pairingCode: string }): Promise<PairDeviceResult> {
  try {
    const settings = await getSettings();
    const pairingCode = normalizePairingCode(input.pairingCode ?? '');
    if (!pairingCode) throw new Error('missing_pairing_code');
    const response = await fetch(buildApiUrl(settings.apiBaseUrl, '/api/client/device/pair'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairingCode,
        deviceName: sanitizeDeviceName(settings.deviceName),
        serverName: settings.serverName,
        appVersion: app.getVersion(),
      }),
    });
    if (!response.ok) throw new Error(`http_${response.status}`);
    const payload = await response.json() as { deviceId?: string; deviceToken?: string; accountName?: string };
    if (!payload.deviceId || !payload.deviceToken) throw new Error('invalid_pairing_response');
    const next = await saveSettings({
      deviceId: payload.deviceId,
      deviceToken: payload.deviceToken,
      accountName: payload.accountName,
      pairedAt: new Date().toISOString(),
    });
    return { ok: true, settings: next };
  } catch (err) {
    return { ok: false, settings: await getSettings(), error: err instanceof Error ? err.message : String(err) };
  }
}
