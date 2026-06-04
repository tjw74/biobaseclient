import { app } from 'electron';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import type { ParsedDemoSummary, UploadQueueItem, ClientSettings } from '../shared/types.js';

const SETTINGS_FILE = 'settings.json';
const QUEUE_FILE = 'upload_queue.json';

function dataPath(name: string) {
  return path.join(app.getPath('userData'), name);
}

function defaultSettings(): ClientSettings {
  return {
    apiBaseUrl: process.env.VITE_BIOBASE_API_URL ?? '',
    deviceName: os.hostname(),
    serverName: process.env.VITE_BIOBASE_SERVER_NAME ?? 'Biobase CS2',
  };
}

async function readJson<T>(file: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await fs.readFile(dataPath(file), 'utf8')) as T;
  } catch {
    return fallback;
  }
}

function normalizeApiBaseUrl(raw: string): string {
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

async function writeJson(file: string, value: unknown): Promise<void> {
  await fs.mkdir(app.getPath('userData'), { recursive: true });
  await fs.writeFile(dataPath(file), JSON.stringify(value, null, 2));
}

export async function getSettings(): Promise<ClientSettings> {
  const saved = await readJson<Partial<ClientSettings>>(SETTINGS_FILE, {});
  return { ...defaultSettings(), ...saved };
}

export async function saveSettings(patch: Partial<ClientSettings>): Promise<ClientSettings> {
  const next = { ...(await getSettings()), ...patch };
  next.apiBaseUrl = normalizeApiBaseUrl(next.apiBaseUrl ?? '');
  next.deviceName = (next.deviceName ?? '').trim() || os.hostname();
  next.serverName = (next.serverName ?? '').trim() || 'Biobase CS2';
  await writeJson(SETTINGS_FILE, next);
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
      const response = await fetch(`${settings.apiBaseUrl}/api/client/sessions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
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
