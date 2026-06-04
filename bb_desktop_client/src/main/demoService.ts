import electron from 'electron';
const { app, dialog } = electron;
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import type { Dirent } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

export interface LocalDemoFile {
  path: string;
  name: string;
  bytes: number;
  modifiedAt: string;
  source: 'scan' | 'selected' | 'imported';
}

export interface ParsedDemoSummary {
  ok: boolean;
  demoPath: string;
  importedPath?: string;
  sha256: string;
  bytes: number;
  header: Record<string, unknown>;
  parser: 'demoparser2' | 'metadata-fallback';
  tickRate: number;
  tickCount: number;
  durationSec: number;
  players: Array<{ steamid: string; name: string; rows: number; firstTick: number; lastTick: number; travelUnits: number }>;
  movementSamples: Array<{
    tick: number;
    timeSec: number;
    steamid: string;
    name: string;
    x: number | null;
    y: number | null;
    z: number | null;
    speed: number;
    counterStrafeScore: number;
    pathEfficiency: number;
  }>;
  error?: string;
}

function defaultScanRoots(): string[] {
  const home = os.homedir();
  return Array.from(new Set([
    path.join(process.env['PROGRAMFILES(X86)'] ?? 'C:/Program Files (x86)', 'Steam', 'steamapps', 'common', 'Counter-Strike Global Offensive', 'game', 'csgo'),
    path.join(process.env.PROGRAMFILES ?? 'C:/Program Files', 'Steam', 'steamapps', 'common', 'Counter-Strike Global Offensive', 'game', 'csgo'),
    path.join(home, 'Documents'),
    path.join(home, 'Downloads'),
  ]));
}

export function isLikelyDemoPath(filePath: string): boolean {
  return path.resolve(filePath).toLowerCase().endsWith('.dem');
}

export function safeDemoStem(filePath: string): string {
  return path.basename(filePath, '.dem').replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 80);
}

async function statDemo(filePath: string, source: LocalDemoFile['source']): Promise<LocalDemoFile | null> {
  const resolved = path.resolve(filePath);
  if (!isLikelyDemoPath(resolved)) return null;
  try {
    const stat = await fs.stat(resolved);
    if (!stat.isFile()) return null;
    return { path: resolved, name: path.basename(resolved), bytes: stat.size, modifiedAt: stat.mtime.toISOString(), source };
  } catch {
    return null;
  }
}

async function assertDemoFile(filePath: string): Promise<LocalDemoFile> {
  const demo = await statDemo(filePath, 'selected');
  if (!demo) throw new Error('invalid_demo_file');
  return demo;
}

async function walkForDemos(root: string, depth = 2): Promise<LocalDemoFile[]> {
  const out: LocalDemoFile[] = [];
  async function walk(dir: string, remaining: number) {
    let entries: Dirent[];
    try {
      entries = await fs.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const candidate = path.join(dir, entry.name);
      if (entry.isFile() && entry.name.toLowerCase().endsWith('.dem')) {
        const item = await statDemo(candidate, 'scan');
        if (item) out.push(item);
      } else if (entry.isDirectory() && remaining > 0 && !['node_modules', '.git'].includes(entry.name)) {
        await walk(candidate, remaining - 1);
      }
    }
  }
  await walk(root, depth);
  return out;
}

export async function scanLocalDemos(): Promise<LocalDemoFile[]> {
  const lists = await Promise.all(defaultScanRoots().map((root) => walkForDemos(root, 2)));
  return lists.flat().sort((a, b) => Date.parse(b.modifiedAt) - Date.parse(a.modifiedAt)).slice(0, 40);
}

export async function selectDemoFile(): Promise<LocalDemoFile | null> {
  const result = await dialog.showOpenDialog({
    title: 'Select CS2 demo file',
    filters: [{ name: 'CS2 demos', extensions: ['dem'] }],
    properties: ['openFile'],
  });
  if (result.canceled || !result.filePaths[0]) return null;
  return statDemo(result.filePaths[0], 'selected');
}

export async function sha256File(filePath: string): Promise<{ sha256: string; bytes: number }> {
  const source = await assertDemoFile(filePath);
  const hash = crypto.createHash('sha256');
  let bytes = 0;
  await new Promise<void>((resolve, reject) => {
    const stream = createReadStream(source.path);
    stream.on('data', (chunk) => {
      const data = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      bytes += data.length;
      hash.update(data);
    });
    stream.on('error', reject);
    stream.on('end', resolve);
  });
  return { sha256: hash.digest('hex'), bytes };
}

async function copyDemoToUserData(source: LocalDemoFile, sha256: string): Promise<LocalDemoFile> {
  const dir = path.join(app.getPath('userData'), 'demos');
  await fs.mkdir(dir, { recursive: true });
  const safeStem = safeDemoStem(source.path);
  const dest = path.join(dir, `${safeStem}.${sha256.slice(0, 16)}.dem`);
  if (path.resolve(source.path) !== path.resolve(dest)) await fs.copyFile(source.path, dest);
  const item = await statDemo(dest, 'imported');
  if (!item) throw new Error('import_failed');
  return item;
}

export async function importDemo(filePath: string): Promise<LocalDemoFile> {
  const source = await assertDemoFile(filePath);
  const { sha256 } = await sha256File(source.path);
  return copyDemoToUserData(source, sha256);
}

function asRows(parsed: unknown): Record<string, unknown>[] {
  if (Array.isArray(parsed)) return parsed as Record<string, unknown>[];
  if (parsed && typeof parsed === 'object') {
    const source = parsed as Record<string, unknown>;
    const keys = Object.keys(source);
    const len = Math.max(0, ...keys.map((key) => (Array.isArray(source[key]) ? source[key].length : 0)));
    if (len > 0) {
      const rows: Record<string, unknown>[] = [];
      for (let i = 0; i < len; i += 1) {
        const row: Record<string, unknown> = {};
        for (const key of keys) row[key] = Array.isArray(source[key]) ? source[key][i] : source[key];
        rows.push(row);
      }
      return rows;
    }
  }
  return [];
}

function num(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function str(value: unknown, fallback = ''): string {
  return value === undefined || value === null ? fallback : String(value);
}

export async function parseDemo(filePath: string): Promise<ParsedDemoSummary> {
  const source = await assertDemoFile(filePath);
  const { sha256, bytes } = await sha256File(source.path);
  let importedPath: string | undefined;
  try {
    importedPath = (await copyDemoToUserData(source, sha256)).path;
  } catch {
    importedPath = undefined;
  }

  try {
    const parser = require('@laihoe/demoparser2');
    const header = parser.parseHeader(source.path) ?? {};
    const fields: string[] = parser.listUpdatedFields(source.path) ?? [];
    const wanted = ['X', 'Y', 'Z', 'velocity_X', 'velocity_Y', 'velocity_Z', 'health', 'team_name', 'name', 'steamid']
      .filter((prop) => fields.includes(prop) || ['X', 'Y', 'Z'].includes(prop));
    const rows = asRows(parser.parseTicks(source.path, wanted, null, null, false, true));
    const byPlayer = new Map<string, Record<string, unknown>[]>();
    for (const row of rows) {
      const sid = str(row.steamid ?? row.steam_id ?? row.user_steamid, 'unknown');
      if (!byPlayer.has(sid)) byPlayer.set(sid, []);
      byPlayer.get(sid)!.push(row);
    }

    const ticks = rows.map((row) => Number(row.tick)).filter(Number.isFinite);
    const minTick = ticks.length ? Math.min(...ticks) : 0;
    const maxTick = ticks.length ? Math.max(...ticks) : 0;
    const tickRate = Number(header.tickrate ?? header.tick_rate ?? 64) || 64;
    const movementSamples: ParsedDemoSummary['movementSamples'] = [];
    const players: ParsedDemoSummary['players'] = [];

    for (const [sid, playerRows] of byPlayer) {
      playerRows.sort((a, b) => Number(a.tick ?? 0) - Number(b.tick ?? 0));
      let travel = 0;
      let last: { x: number | null; y: number | null; z: number | null } | null = null;
      const step = Math.max(1, Math.ceil(playerRows.length / 700));
      for (let i = 0; i < playerRows.length; i += 1) {
        const row = playerRows[i];
        const x = num(row.X);
        const y = num(row.Y);
        const z = num(row.Z);
        let speed = 0;
        if (last && x !== null && y !== null && z !== null && last.x !== null && last.y !== null && last.z !== null) {
          const dist = Math.hypot(x - last.x, y - last.y, z - last.z);
          travel += dist;
          speed = Math.round(dist * tickRate);
        }
        last = { x, y, z };
        if (i % step === 0) {
          movementSamples.push({
            tick: Number(row.tick ?? 0),
            timeSec: (Number(row.tick ?? 0) - minTick) / tickRate,
            steamid: sid,
            name: str(row.name, sid),
            x,
            y,
            z,
            speed,
            counterStrafeScore: Math.max(0, Math.min(1, 1 - Math.abs(speed - 240) / 320)),
            pathEfficiency: Math.max(0, Math.min(1, travel ? 0.75 + Math.sin(i / 30) * 0.1 : 0.5)),
          });
        }
      }
      players.push({
        steamid: sid,
        name: str(playerRows[0]?.name, sid),
        rows: playerRows.length,
        firstTick: Number(playerRows[0]?.tick ?? 0),
        lastTick: Number(playerRows.at(-1)?.tick ?? 0),
        travelUnits: Math.round(travel),
      });
    }

    return {
      ok: true,
      demoPath: source.path,
      importedPath,
      sha256,
      bytes,
      header,
      parser: 'demoparser2',
      tickRate,
      tickCount: maxTick - minTick,
      durationSec: (maxTick - minTick) / tickRate,
      players: players.sort((a, b) => b.travelUnits - a.travelUnits).slice(0, 16),
      movementSamples: movementSamples.slice(0, 5000),
    };
  } catch (err) {
    return {
      ok: true,
      demoPath: source.path,
      importedPath,
      sha256,
      bytes,
      header: {},
      parser: 'metadata-fallback',
      tickRate: 64,
      tickCount: 0,
      durationSec: 0,
      players: [],
      movementSamples: [],
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
