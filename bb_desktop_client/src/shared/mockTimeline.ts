import type { BiobaseMatch, MovementSample, TimelineFrame } from './types.js';

export const mockMatch: BiobaseMatch = {
  id: 'local-demo-akani-001',
  map: 'de_ancient',
  startedAt: '2026-06-04T15:54:47Z',
  demoPath: 'C:/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive/game/csgo/replays/biobase_demo.dem',
  serverName: 'Biobase CS2',
};

export function movementAt(timeSec: number): MovementSample {
  const tick = Math.round(timeSec * 64);
  const wave = Math.sin(timeSec / 3);
  return {
    tick,
    timeSec,
    speed: Math.round(230 + wave * 62),
    acceleration: Math.round(18 + Math.cos(timeSec / 2) * 10),
    counterStrafeScore: Number((0.72 + Math.sin(timeSec / 5) * 0.18).toFixed(2)),
    pathEfficiency: Number((0.81 + Math.cos(timeSec / 7) * 0.08).toFixed(2)),
    keys: {
      w: Math.sin(timeSec) > -0.2,
      a: Math.sin(timeSec / 1.7) > 0.35,
      s: false,
      d: Math.cos(timeSec / 1.7) > 0.35,
      crouch: Math.sin(timeSec / 4) > 0.85,
      jump: Math.cos(timeSec / 6) > 0.92,
    },
  };
}

export function frameAt(timeSec: number): TimelineFrame {
  const movement = movementAt(timeSec);
  return {
    match: mockMatch,
    currentTimeSec: timeSec,
    currentTick: movement.tick,
    movement,
    sensors: [
      { timeSec, channel: 'EMG-L', value: Number((0.34 + Math.sin(timeSec / 2) * 0.12).toFixed(3)), unit: 'normalized' },
      { timeSec, channel: 'EMG-R', value: Number((0.29 + Math.cos(timeSec / 2.4) * 0.1).toFixed(3)), unit: 'normalized' },
    ],
  };
}
