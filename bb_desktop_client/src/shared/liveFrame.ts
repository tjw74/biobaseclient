import type { LiveMovementSample, LiveServerStatus } from './liveTypes.js';
import type { BiobaseMatch, TimelineFrame } from './types.js';
import { DEFAULT_CONNECT } from './biobaseEndpoints.js';

export { DEFAULT_API_BASE_URL, DEFAULT_CONNECT } from './biobaseEndpoints.js';

const DEFAULT_TICKRATE = 64;

function offlineFrame(status: LiveServerStatus | null): TimelineFrame {
  const connect = status?.connect ?? DEFAULT_CONNECT;
  return {
    match: {
      id: 'live-session',
      map: status?.map ?? 'live-server',
      startedAt: status?.polledAt ?? new Date().toISOString(),
      demoPath: connect.console,
      serverName: status?.hostname ?? 'Biobase CS2',
    },
    currentTimeSec: 0,
    currentTick: 0,
    movement: {
      tick: 0,
      timeSec: 0,
      name: status?.ok ? 'WAITING' : 'OFFLINE',
      speed: 0,
      acceleration: 0,
      counterStrafeScore: 0,
      pathEfficiency: 0,
      keys: { w: false, a: false, s: false, d: false, crouch: false, jump: false },
    },
    sensors: [],
  };
}

export function buildLiveFrame(
  status: LiveServerStatus | null,
  movement: LiveMovementSample | null | undefined,
): TimelineFrame {
  if (!movement) return offlineFrame(status);
  const enriched = movement;
  const connect = status?.connect ?? DEFAULT_CONNECT;
  const tick = enriched.tick ?? 0;
  const match: BiobaseMatch = {
    id: 'live-session',
    map: status?.map ?? 'live-server',
    startedAt: status?.polledAt ?? enriched.observedAt ?? new Date().toISOString(),
    demoPath: connect.console,
    serverName: status?.hostname ?? 'Biobase CS2',
  };
  return {
    match,
    currentTick: tick,
    currentTimeSec: tick / DEFAULT_TICKRATE,
    movement: {
      tick,
      timeSec: tick / DEFAULT_TICKRATE,
      steamid: enriched.steamid,
      name: enriched.player ?? 'LIVE',
      speed: Math.round(enriched.speed ?? 0),
      acceleration: Math.round(Math.hypot(enriched.vel[0], enriched.vel[1], enriched.vel[2])),
      counterStrafeScore: enriched.counterStrafeScore ?? 0.5,
      pathEfficiency: enriched.pathEfficiency ?? 0.7,
      x: enriched.pos[0],
      y: enriched.pos[1],
      z: enriched.pos[2],
      keys: enriched.keys ?? {
        w: false,
        a: false,
        s: false,
        d: false,
        crouch: false,
        jump: !enriched.on_ground,
      },
    },
    sensors: [],
  };
}
