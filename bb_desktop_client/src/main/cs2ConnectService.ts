import electron from 'electron';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { ensureCs2WindowedLaunch } from './cs2LaunchService.js';
import { buildSteamConnectUrl, DEFAULT_CONNECT } from '../shared/biobaseEndpoints.js';

const { clipboard, shell, app } = electron;

export function isCs2Running(): boolean {
  try {
    const out = execSync('tasklist /FI "IMAGENAME eq cs2.exe" /NH', { timeout: 3000, encoding: 'utf8' });
    return out.includes('cs2.exe');
  } catch {
    return false;
  }
}

export type ConnectCs2Result =
  | { ok: true; url: string; host: string; port: number }
  | { ok: false; error: string };

export type CopyConnectResult = { ok: true; text: string } | { ok: false; error: string };

export type DesktopShortcutResult = { ok: true; path: string } | { ok: false; error: string };

function resolveTarget(host?: string, port?: number) {
  return {
    host: (host ?? DEFAULT_CONNECT.host).trim(),
    port: port ?? DEFAULT_CONNECT.port,
  };
}

export async function connectToCs2Server(host?: string, port?: number): Promise<ConnectCs2Result> {
  const target = resolveTarget(host, port);
  await ensureCs2WindowedLaunch();
  const url = buildSteamConnectUrl(target.host, target.port);
  try {
    await shell.openExternal(url);
    createCs2DesktopShortcut(host, port);
    return { ok: true, url, host: target.host, port: target.port };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message };
  }
}

export function createCs2DesktopShortcut(host?: string, port?: number): DesktopShortcutResult {
  const target = resolveTarget(host, port);
  const url = buildSteamConnectUrl(target.host, target.port);
  try {
    const desktop = app.getPath('desktop');
    const filePath = path.join(desktop, 'Play Biobase CS2.url');
    fs.writeFileSync(filePath, `[InternetShortcut]\r\nURL=${url}\r\n`, 'ascii');
    return { ok: true, path: filePath };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message };
  }
}

export function copyConnectCommand(host?: string, port?: number): CopyConnectResult {
  const target = resolveTarget(host, port);
  const text = `connect ${target.host}:${target.port}`;
  try {
    clipboard.writeText(text);
    return { ok: true, text };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message };
  }
}
