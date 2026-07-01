import electron from 'electron';
const { app, dialog } = electron;
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import type { Dirent } from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { defaultScanRoots } from './scanRoots.js';
import type { DemoEvent, DemoFrame, LocalDemoFile, ParsedDemoSummary, PlayerState } from '../shared/types.js';

const require = createRequire(import.meta.url);

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

function bool(value: unknown): boolean | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const s = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'y'].includes(s)) return true;
  if (['0', 'false', 'no', 'n'].includes(s)) return false;
  return undefined;
}

function str(value: unknown, fallback = ''): string {
  return value === undefined || value === null ? fallback : String(value);
}

function finiteTick(row: Record<string, unknown>): number | null {
  const tick = num(row.tick ?? row.game_tick ?? row.gameTick ?? row.tick_number);
  return tick === null ? null : Math.round(tick);
}

function teamFromNumber(value: unknown): PlayerState['team'] | null {
  const n = num(value);
  if (n === 2) return 'T';
  if (n === 3) return 'CT';
  return null;
}

function teamFromRow(row: Record<string, unknown>): PlayerState['team'] {
  const numeric = teamFromNumber(row.team_num ?? row.team_number ?? row.teamNumber);
  if (numeric) return numeric;
  const team = str(row.team_name ?? row.team, '').toLowerCase();
  if (team.includes('terrorist') || team === 't' || team === 'team_t') return 'T';
  if (team.includes('counter') || team.includes('ct') || team === 'team_ct') return 'CT';
  return 'UNKNOWN';
}

function normalizePlayerState(row: Record<string, unknown>): PlayerState | null {
  const x = num(row.X ?? row.x);
  const y = num(row.Y ?? row.y);
  if (x === null || y === null) return null;

  const sid = str(row.steamid ?? row.steam_id ?? row.user_steamid ?? row.userid ?? row.user_id, 'unknown');
  const name = str(row.name ?? row.player_name ?? row.playerName, sid);
  const player: PlayerState = { steamid: sid, name, team: teamFromRow(row), x, y };
  const z = num(row.Z ?? row.z);
  const yaw = num(row.yaw ?? row.eye_yaw ?? row.eyeYaw ?? row.Yaw);
  const pitch = num(row.pitch ?? row.eye_pitch ?? row.eyePitch ?? row.Pitch);
  const health = num(row.health ?? row.hp);
  const hasHelmet = bool(row.has_helmet ?? row.hasHelmet);
  const hasDefuser = bool(row.has_defuser ?? row.hasDefuser);
  const isScoped = bool(row.is_scoped ?? row.isScoped);
  const isAlive = bool(row.is_alive ?? row.isAlive);
  const lifeState = num(row.life_state ?? row.lifeState);
  const activeWeapon = row.active_weapon ?? row.weapon_name ?? row.weaponName;

  if (z !== null) player.z = z;
  if (yaw !== null) player.yaw = yaw;
  if (pitch !== null) player.pitch = pitch;
  if (health !== null) player.health = health;
  if (hasHelmet !== undefined) player.hasHelmet = hasHelmet;
  if (hasDefuser !== undefined) player.hasDefuser = hasDefuser;
  if (isScoped !== undefined) player.isScoped = isScoped;
  if (isAlive !== undefined) player.isAlive = isAlive;
  else if (lifeState !== null) player.isAlive = lifeState === 0;
  else if (health !== null) player.isAlive = health > 0;
  if (activeWeapon !== undefined && activeWeapon !== null) {
    player.activeWeapon = typeof activeWeapon === 'number' || typeof activeWeapon === 'string' ? activeWeapon : String(activeWeapon);
  }
  return player;
}

function demoMapName(header: Record<string, unknown>, fallbackPath: string): string {
  return str(header.map_name ?? header.mapName ?? header.map ?? header.MapName, safeDemoStem(fallbackPath) || 'unknown');
}

function readDemoEvents(parser: any, demoPath: string, eventNames: string[], tickRate: number, minTick: number): DemoEvent[] {
  const rows: Record<string, unknown>[] = [];
  try {
    if (typeof parser.parseEvents === 'function') rows.push(...asRows(parser.parseEvents(demoPath, eventNames)));
  } catch {
    // Some demoparser2 builds expose parseEvent only. Fall through to per-event reads.
  }
  if (rows.length === 0 && typeof parser.parseEvent === 'function') {
    for (const eventName of eventNames) {
      try {
        for (const row of asRows(parser.parseEvent(demoPath, eventName))) rows.push({ event_name: eventName, ...row });
      } catch {
        // Unknown event names are non-fatal for playback.
      }
    }
  }

  return rows
    .map((row) => {
      const tick = finiteTick(row);
      if (tick === null) return null;
      const type = str(row.event_name ?? row.eventName ?? row.name ?? row.type, 'event');
      return { tick, timeSec: Math.max(0, (tick - minTick) / tickRate), type, data: row } satisfies DemoEvent;
    })
    .filter((event): event is DemoEvent => Boolean(event))
    .sort((a, b) => a.tick - b.tick);
}

function safeJsonReplacer(_key: string, value: unknown): unknown {
  return typeof value === 'bigint' ? value.toString() : value;
}

export async function parseDemo(filePath: string): Promise<ParsedDemoSummary> {
  const source = await assertDemoFile(filePath);
  const { sha256, bytes } = await sha256File(source.path);
  const demoId = sha256.slice(0, 24);
  let importedPath: string | undefined;
  try {
    importedPath = (await copyDemoToUserData(source, sha256)).path;
  } catch {
    importedPath = undefined;
  }

  try {
    const parser = require('@laihoe/demoparser2');
    const header = (parser.parseHeader(source.path) ?? {}) as Record<string, unknown>;
    const fields: string[] = Array.isArray(parser.listUpdatedFields?.(source.path)) ? parser.listUpdatedFields(source.path) : [];
    const wantedCandidates = [
      'X', 'Y', 'Z', 'yaw', 'pitch', 'eye_yaw', 'eye_pitch',
      'velocity_X', 'velocity_Y', 'velocity_Z',
      'health', 'is_alive', 'life_state',
      'team_name', 'team_num', 'team_number',
      'name', 'player_name', 'steamid', 'steam_id', 'user_steamid', 'userid',
      'has_helmet', 'has_defuser', 'is_scoped', 'active_weapon', 'weapon_name',
    ];
    const alwaysSafe = new Set(['X', 'Y', 'Z']);
    const wanted = wantedCandidates.filter((prop) => alwaysSafe.has(prop) || fields.includes(prop));
    const rows = asRows(parser.parseTicks(source.path, wanted, null, null, false, true));
    const tickRows = rows
      .map((row) => ({ row, tick: finiteTick(row) }))
      .filter((item): item is { row: Record<string, unknown>; tick: number } => item.tick !== null)
      .sort((a, b) => a.tick - b.tick);
    const byPlayer = new Map<string, Record<string, unknown>[]>();
    for (const { row } of tickRows) {
      const sid = str(row.steamid ?? row.steam_id ?? row.user_steamid ?? row.userid ?? row.user_id, 'unknown');
      if (!byPlayer.has(sid)) byPlayer.set(sid, []);
      byPlayer.get(sid)!.push(row);
    }

    const minTick = tickRows.length ? tickRows[0].tick : 0;
    const maxTick = tickRows.length ? tickRows[tickRows.length - 1].tick : 0;
    const tickRate = Number(header.tickrate ?? header.tick_rate ?? header.tickRate ?? 64) || 64;
    const mapName = demoMapName(header, source.path);
    const movementSamples: ParsedDemoSummary['movementSamples'] = [];
    const players: ParsedDemoSummary['players'] = [];

    for (const [sid, playerRows] of byPlayer) {
      playerRows.sort((a, b) => Number(a.tick ?? 0) - Number(b.tick ?? 0));
      let travel = 0;
      let last: { x: number | null; y: number | null; z: number | null } | null = null;
      const step = Math.max(1, Math.ceil(playerRows.length / 700));
      for (let i = 0; i < playerRows.length; i += 1) {
        const row = playerRows[i];
        const x = num(row.X ?? row.x);
        const y = num(row.Y ?? row.y);
        const z = num(row.Z ?? row.z);
        let speed = 0;
        if (last && x !== null && y !== null && z !== null && last.x !== null && last.y !== null && last.z !== null) {
          const dist = Math.hypot(x - last.x, y - last.y, z - last.z);
          travel += dist;
          speed = Math.round(dist * tickRate);
        }
        last = { x, y, z };
        if (i % step === 0) {
          const tick = Number(row.tick ?? 0);
          movementSamples.push({
            tick,
            timeSec: (tick - minTick) / tickRate,
            steamid: sid,
            name: str(row.name ?? row.player_name, sid),
            x,
            y,
            z,
            speed,
            counterStrafeScore: Math.max(0, Math.min(1, 1 - Math.abs(speed - 240) / 320)),
            pathEfficiency: Math.max(0, Math.min(1, travel ? 0.75 + Math.sin(i / 30) * 0.1 : 0.5)),
          });
        }
      }
      const lastRow = playerRows[playerRows.length - 1];
      players.push({
        steamid: sid,
        name: str(playerRows[0]?.name ?? playerRows[0]?.player_name, sid),
        rows: playerRows.length,
        firstTick: Number(playerRows[0]?.tick ?? 0),
        lastTick: Number(lastRow?.tick ?? 0),
        travelUnits: Math.round(travel),
      });
    }

    const frameStepTicks = Math.max(1, Math.round(tickRate / 6));
    const frameMap = new Map<number, Map<string, PlayerState>>();
    for (const { row, tick } of tickRows) {
      if (tick !== minTick && tick !== maxTick && (tick - minTick) % frameStepTicks !== 0) continue;
      const player = normalizePlayerState(row);
      if (!player) continue;
      if (!frameMap.has(tick)) frameMap.set(tick, new Map<string, PlayerState>());
      frameMap.get(tick)!.set(player.steamid, player);
    }
    const rawFrames: DemoFrame[] = [...frameMap.entries()]
      .map(([tick, playerMap]) => ({ tick, timeSec: Math.max(0, (tick - minTick) / tickRate), players: [...playerMap.values()] }))
      .filter((frame) => frame.players.length > 0)
      .sort((a, b) => a.tick - b.tick);
    const maxFrames = 5000;
    const frameStride = Math.max(1, Math.ceil(rawFrames.length / maxFrames));
    const frames = rawFrames.filter((_frame, index) => index % frameStride === 0);
    const lastRawFrame = rawFrames[rawFrames.length - 1];
    const lastFrame = frames[frames.length - 1];
    if (lastRawFrame && lastFrame?.tick !== lastRawFrame.tick) frames.push(lastRawFrame);

    const events = readDemoEvents(
      parser,
      source.path,
      ['player_death', 'player_hurt', 'weapon_fire', 'bomb_planted', 'bomb_defused', 'bomb_exploded', 'round_start', 'round_end'],
      tickRate,
      minTick,
    );

    const parsed: ParsedDemoSummary = {
      ok: true,
      demoId,
      demoPath: source.path,
      importedPath,
      sha256,
      bytes,
      header,
      parser: 'demoparser2',
      tickRate,
      tickCount: maxTick - minTick,
      durationSec: (maxTick - minTick) / tickRate,
      mapName,
      startTick: minTick,
      endTick: maxTick,
      frames,
      events,
      players: players.sort((a, b) => b.travelUnits - a.travelUnits).slice(0, 16),
      movementSamples: movementSamples.slice(0, 5000),
    };

    const parsedDir = path.join(app.getPath('userData'), 'parsed-demos');
    await fs.mkdir(parsedDir, { recursive: true });
    await fs.writeFile(path.join(parsedDir, `${demoId}.json`), JSON.stringify(parsed, safeJsonReplacer, 2), 'utf8').catch(() => undefined);

    return parsed;
  } catch (err) {
    return {
      ok: true,
      demoId,
      demoPath: source.path,
      importedPath,
      sha256,
      bytes,
      header: {},
      parser: 'metadata-fallback',
      tickRate: 64,
      tickCount: 0,
      durationSec: 0,
      mapName: 'unknown',
      startTick: 0,
      endTick: 0,
      frames: [],
      events: [],
      players: [],
      movementSamples: [],
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
