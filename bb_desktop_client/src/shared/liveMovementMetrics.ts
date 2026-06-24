import type { LiveMovementSample } from './liveTypes.js';

const HISTORY_LIMIT = 24;

const historyBySteam = new Map<string, LiveMovementSample[]>();

function historyKey(sample: LiveMovementSample): string {
  return sample.steamid || sample.player || 'unknown';
}

export function rememberLiveSample(sample: LiveMovementSample): LiveMovementSample[] {
  const key = historyKey(sample);
  const existing = historyBySteam.get(key) ?? [];
  const next = [...existing, sample].slice(-HISTORY_LIMIT);
  historyBySteam.set(key, next);
  return next;
}

function angleDiff(a: number, b: number): number {
  let diff = Math.abs(a - b) % 360;
  if (diff > 180) diff = 360 - diff;
  return diff;
}

function velocityHeading(vel: [number, number, number]): number | null {
  const [vx, vy] = vel;
  const speed2d = Math.hypot(vx, vy);
  if (speed2d < 8) return null;
  return (Math.atan2(vy, vx) * 180) / Math.PI;
}

export function inferMovementKeys(sample: LiveMovementSample): LiveMovementSample['keys'] {
  const heading = velocityHeading(sample.vel);
  const yaw = sample.yaw ?? 0;
  const speed2d = Math.hypot(sample.vel[0], sample.vel[1]);
  if (heading === null) {
    return { w: false, a: false, s: false, d: false, crouch: false, jump: !sample.on_ground };
  }
  const rel = angleDiff(heading, yaw);
  const movingForward = rel <= 45;
  const movingBack = rel >= 135;
  const movingLeft = rel > 45 && rel < 135 && sample.vel[0] < 0;
  const movingRight = rel > 45 && rel < 135 && sample.vel[0] > 0;
  return {
    w: movingForward && speed2d > 8,
    s: movingBack && speed2d > 8,
    a: movingLeft && speed2d > 8,
    d: movingRight && speed2d > 8,
    crouch: false,
    jump: !sample.on_ground,
  };
}

export function computeCounterStrafeScore(history: LiveMovementSample[]): number {
  if (history.length < 2) return 0.5;
  const current = history[history.length - 1];
  const previous = history[history.length - 2];
  const [cvx, cvy] = current.vel;
  const [pvx, pvy] = previous.vel;
  const currentSpeed = Math.hypot(cvx, cvy);
  const previousSpeed = Math.hypot(pvx, pvy);
  if (currentSpeed < 40 || previousSpeed < 40) return 0.55;
  const dot = cvx * pvx + cvy * pvy;
  if (dot >= 0) return 0.45;
  const alignment = Math.min(1, (-dot) / (currentSpeed * previousSpeed));
  return Number(Math.min(0.98, 0.55 + alignment * 0.4).toFixed(2));
}

export function computePathEfficiency(history: LiveMovementSample[]): number {
  if (history.length < 3) return 0.7;
  const first = history[0];
  const last = history[history.length - 1];
  const straight = Math.hypot(last.pos[0] - first.pos[0], last.pos[1] - first.pos[1]);
  let path = 0;
  for (let i = 1; i < history.length; i += 1) {
    const prev = history[i - 1];
    const next = history[i];
    path += Math.hypot(next.pos[0] - prev.pos[0], next.pos[1] - prev.pos[1]);
  }
  if (path <= 1) return 0.7;
  return Number(Math.min(0.99, Math.max(0.2, straight / path)).toFixed(2));
}

export function enrichLiveSample(sample: LiveMovementSample): LiveMovementSample {
  const history = rememberLiveSample(sample);
  return {
    ...sample,
    counterStrafeScore: computeCounterStrafeScore(history),
    pathEfficiency: computePathEfficiency(history),
    keys: inferMovementKeys(sample),
  };
}
