export type DemoTick = number;

export interface BiobaseMatch {
  id: string;
  map: string;
  startedAt: string;
  demoPath: string;
  serverName: string;
}

export interface LocalDemoFile {
  path: string;
  name: string;
  bytes: number;
  modifiedAt: string;
  source: 'scan' | 'selected' | 'imported';
}

export interface MovementSample {
  tick: DemoTick;
  timeSec: number;
  steamid?: string;
  name?: string;
  speed: number;
  acceleration: number;
  counterStrafeScore: number;
  pathEfficiency: number;
  x?: number | null;
  y?: number | null;
  z?: number | null;
  keys: { w: boolean; a: boolean; s: boolean; d: boolean; crouch: boolean; jump: boolean };
}

export interface SensorSample {
  timeSec: number;
  channel: string;
  value: number;
  unit: 'uv' | 'mv' | 'normalized';
}

export interface TimelineFrame {
  match: BiobaseMatch;
  currentTimeSec: number;
  currentTick: DemoTick;
  movement: MovementSample;
  sensors: SensorSample[];
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

export interface PlaybackState {
  matchId: string;
  demoPath: string;
  startedAtMs: number;
  offsetSec: number;
  playing: boolean;
  currentTimeSec: number;
}

export interface ClientSettings {
  apiBaseUrl: string;
  deviceName: string;
  serverName: string;
  deviceId?: string;
  deviceToken?: string;
  accountName?: string;
  pairedAt?: string;
  trackedPlayerName?: string;
  trackedSteamId?: string;
  /** When true (default), this client advertises live stats on the server. */
  shareStatsOnServer?: boolean;
  /** Stable id for optional presence heartbeats (generated on first run). */
  presenceSessionId?: string;
  /** Set after user confirms first HUD overlay warning dialog. */
  overlayHudConfirmed?: boolean;
}

export interface PairDeviceInput {
  pairingCode: string;
}

export interface PairDeviceResult {
  ok: boolean;
  settings: ClientSettings;
  error?: string;
}

export interface UploadQueueItem {
  id: string;
  sha256: string;
  demoName: string;
  status: 'queued' | 'uploading' | 'uploaded' | 'failed';
  attempts: number;
  createdAt: string;
  updatedAt: string;
  uploadedAt?: string;
  lastError?: string;
  payload: ParsedDemoSummary;
}
