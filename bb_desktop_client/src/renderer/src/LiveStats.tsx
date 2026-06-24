import React from 'react';
import type { TimelineFrame } from '../../shared/types';

export type StatsSurface = 'dashboard' | 'overlay';

function Key({ label, active }: { label: string; active: boolean }) {
  return <span className={active ? 'key active' : 'key'}>{label}</span>;
}

function StatCell({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="stat-cell">
      <b>{value}</b>
      <span>{label}</span>
    </div>
  );
}

export function StatsCategory({
  title,
  status,
  children,
  surface,
}: {
  title: string;
  status?: 'live' | 'soon' | 'idle';
  children: React.ReactNode;
  surface: StatsSurface;
}) {
  const statusLabel = status === 'live' ? 'live' : status === 'soon' ? 'soon' : 'waiting';
  return (
    <section className={`stats-category stats-category--${surface}`}>
      <div className="stats-category-head">
        <h3>{title}</h3>
        <span className={`stats-badge stats-badge--${status ?? 'idle'}`}>{statusLabel}</span>
      </div>
      {children}
    </section>
  );
}

export function MovementStatsBlock({
  frame,
  live,
  surface,
}: {
  frame: TimelineFrame;
  live?: boolean;
  surface: StatsSurface;
}) {
  const movement = frame.movement;
  return (
    <StatsCategory title="Movement" status={live ? 'live' : 'idle'} surface={surface}>
      <div className={`stat-grid stat-grid--${surface}`}>
        <StatCell label="speed" value={movement.speed} />
        <StatCell label="counter" value={movement.counterStrafeScore.toFixed(2)} />
        <StatCell label="path" value={movement.pathEfficiency.toFixed(2)} />
        {surface === 'dashboard' ? <StatCell label="tick" value={frame.currentTick} /> : null}
      </div>
      <div className="keys">
        <Key label="W" active={movement.keys.w} />
        <Key label="A" active={movement.keys.a} />
        <Key label="S" active={movement.keys.s} />
        <Key label="D" active={movement.keys.d} />
        <Key label="J" active={movement.keys.jump} />
        <Key label="C" active={movement.keys.crouch} />
      </div>
    </StatsCategory>
  );
}

export function ShootingStatsPlaceholder({ surface }: { surface: StatsSurface }) {
  return (
    <StatsCategory title="Shooting" status="soon" surface={surface}>
      <p className="stats-soon">Accuracy, spray, and crosshair placement — coming in a later update.</p>
    </StatsCategory>
  );
}

export function LiveStatsPanel({
  frame,
  live,
  playerName,
  mapName,
  surface,
  overlayHint,
}: {
  frame: TimelineFrame;
  live?: boolean;
  playerName?: string | null;
  mapName?: string | null;
  surface: StatsSurface;
  overlayHint?: boolean;
}) {
  return (
    <div className={`live-stats live-stats--${surface}`}>
      <div className="live-stats-head">
        <span className="live-stats-brand">{live ? 'Biobase LIVE' : 'Biobase'}</span>
        <span className="live-stats-meta">{playerName ?? mapName ?? '—'}</span>
      </div>
      <MovementStatsBlock frame={frame} live={live} surface={surface} />
      {surface === 'dashboard' ? <ShootingStatsPlaceholder surface={surface} /> : null}
      {overlayHint ? (
        <div className="hud-hint">Ctrl+Shift+M free mouse · Ctrl+Shift+O toggle · Esc hide</div>
      ) : null}
    </div>
  );
}
