import electron from 'electron';
import { BIOBASE_CS2_HOST, DEFAULT_API_BASE_URL } from '../shared/biobaseEndpoints.js';

const { session } = electron;

/** HTTPS GET — Chromium session.fetch (same stack as Edge on the same PC). */
export async function fetchAdminJson(path: string, timeoutMs = 12000): Promise<{ status: number; text: string }> {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  const url = `https://${BIOBASE_CS2_HOST}${normalizedPath}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await session.defaultSession.fetch(url, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    return { status: response.status, text: await response.text() };
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error('request_timeout');
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

export async function postAdminJson(
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
  timeoutMs = 12000,
): Promise<{ status: number; text: string }> {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  const url = `https://${BIOBASE_CS2_HOST}${normalizedPath}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await session.defaultSession.fetch(url, {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    return { status: response.status, text: await response.text() };
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error('request_timeout');
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

export function adminApiPath(endpoint: string): string {
  const suffix = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
  return `/admin${suffix}`;
}

export { DEFAULT_API_BASE_URL };
