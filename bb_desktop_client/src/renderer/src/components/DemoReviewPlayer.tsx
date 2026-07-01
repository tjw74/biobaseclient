import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { DemoEvent, DemoFrame, DemoLabel, ParsedDemoSummary, PlayerState } from '../../../shared/types';
import './DemoReviewPlayer.css';

type Bounds = { minX: number; maxX: number; minY: number; maxY: number };

const TEAM_COLORS: Record<PlayerState['team'], string> = {
  T: '#f59e0b',
  CT: '#60a5fa',
  UNKNOWN: '#94a3b8',
};

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function formatTimeFromTick(tick: number, startTick: number, tickRate: number): string {
  const seconds = Math.max(0, (tick - startTick) / Math.max(1, tickRate));
  const minutes = Math.floor(seconds / 60);
  const sec = Math.floor(seconds % 60).toString().padStart(2, '0');
  return `${minutes}:${sec}`;
}

function storageKeyFor(parsed: ParsedDemoSummary): string {
  return `biobase.demo.labels.${parsed.demoId ?? parsed.sha256}`;
}

function readLabels(key: string): DemoLabel[] {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as DemoLabel[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeLabels(key: string, labels: DemoLabel[]) {
  try {
    localStorage.setItem(key, JSON.stringify(labels));
  } catch {
    // Label persistence is best-effort; playback should never fail because storage is full/blocked.
  }
}

function newLabelId(): string {
  const webCrypto = globalThis.crypto as Crypto | undefined;
  if (webCrypto && typeof webCrypto.randomUUID === 'function') return webCrypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function boundsForFrames(frames: DemoFrame[]): Bounds {
  let minX = Number.POSITIVE_INFINITY;
  let minY = Number.POSITIVE_INFINITY;
  let maxX = Number.NEGATIVE_INFINITY;
  let maxY = Number.NEGATIVE_INFINITY;
  for (const frame of frames) {
    for (const player of frame.players) {
      minX = Math.min(minX, player.x);
      maxX = Math.max(maxX, player.x);
      minY = Math.min(minY, player.y);
      maxY = Math.max(maxY, player.y);
    }
  }
  if (!Number.isFinite(minX) || !Number.isFinite(minY) || !Number.isFinite(maxX) || !Number.isFinite(maxY)) {
    return { minX: -1000, maxX: 1000, minY: -1000, maxY: 1000 };
  }
  const paddingX = Math.max(500, (maxX - minX) * 0.08);
  const paddingY = Math.max(500, (maxY - minY) * 0.08);
  return { minX: minX - paddingX, maxX: maxX + paddingX, minY: minY - paddingY, maxY: maxY + paddingY };
}

function frameIndexAt(frames: DemoFrame[], tick: number): number {
  if (frames.length === 0) return -1;
  let lo = 0;
  let hi = frames.length - 1;
  let answer = 0;
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (frames[mid].tick <= tick) {
      answer = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return answer;
}

function interpolatePlayers(frames: DemoFrame[], tick: number): PlayerState[] {
  const index = frameIndexAt(frames, tick);
  if (index < 0) return [];
  const left = frames[index];
  const right = frames[Math.min(index + 1, frames.length - 1)];
  if (!right || right.tick === left.tick) return left.players;
  const t = clamp((tick - left.tick) / (right.tick - left.tick), 0, 1);
  const rightById = new Map(right.players.map((player) => [player.steamid, player]));
  const merged = left.players.map((player) => {
    const next = rightById.get(player.steamid);
    if (!next) return player;
    return {
      ...player,
      team: next.team ?? player.team,
      name: next.name ?? player.name,
      x: lerp(player.x, next.x, t),
      y: lerp(player.y, next.y, t),
      z: player.z !== undefined && next.z !== undefined ? lerp(player.z, next.z, t) : next.z ?? player.z,
      yaw: next.yaw ?? player.yaw,
      pitch: next.pitch ?? player.pitch,
      health: next.health ?? player.health,
      isAlive: next.isAlive ?? player.isAlive,
      hasHelmet: next.hasHelmet ?? player.hasHelmet,
      hasDefuser: next.hasDefuser ?? player.hasDefuser,
      isScoped: next.isScoped ?? player.isScoped,
      activeWeapon: next.activeWeapon ?? player.activeWeapon,
    };
  });
  for (const player of right.players) {
    if (!left.players.some((leftPlayer) => leftPlayer.steamid === player.steamid)) merged.push(player);
  }
  return merged;
}

function drawPlayer(ctx: CanvasRenderingContext2D, player: PlayerState, point: { x: number; y: number }) {
  const alive = player.isAlive !== false && (player.health ?? 1) > 0;
  const color = alive ? TEAM_COLORS[player.team] : '#475569';
  ctx.save();
  ctx.globalAlpha = alive ? 1 : 0.5;
  ctx.fillStyle = color;
  ctx.strokeStyle = 'rgba(226, 232, 240, 0.75)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.arc(point.x, point.y, 6, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  if (player.yaw !== undefined) {
    const radians = (-player.yaw * Math.PI) / 180;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(point.x, point.y);
    ctx.lineTo(point.x + Math.cos(radians) * 18, point.y + Math.sin(radians) * 18);
    ctx.stroke();
  }

  ctx.font = '11px Inter, system-ui, sans-serif';
  ctx.fillStyle = '#e2e8f0';
  ctx.textBaseline = 'middle';
  ctx.fillText(player.name || player.steamid, point.x + 10, point.y - 8);
  if (player.health !== undefined) {
    ctx.fillStyle = player.health > 40 ? '#94a3b8' : '#f87171';
    ctx.fillText(`${Math.max(0, Math.round(player.health))}hp`, point.x + 10, point.y + 7);
  }
  ctx.restore();
}

function recentEvents(events: DemoEvent[], tick: number, tickRate: number): DemoEvent[] {
  const windowTicks = Math.max(64, tickRate * 3);
  return events
    .filter((event) => Math.abs(event.tick - tick) <= windowTicks)
    .sort((a, b) => b.tick - a.tick)
    .slice(0, 7);
}

export function DemoReviewPlayer({ parsed }: { parsed: ParsedDemoSummary }) {
  const frames = parsed.frames ?? [];
  const events = parsed.events ?? [];
  const startTick = parsed.startTick ?? frames[0]?.tick ?? 0;
  const endTick = parsed.endTick ?? frames[frames.length - 1]?.tick ?? startTick;
  const tickRate = parsed.tickRate || 64;
  const storageKey = storageKeyFor(parsed);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [currentTick, setCurrentTick] = useState(startTick);
  const [playing, setPlaying] = useState(false);
  const [labelState, setLabelState] = useState<{ key: string; labels: DemoLabel[] }>(() => ({ key: storageKey, labels: readLabels(storageKey) }));
  const [labelStartTick, setLabelStartTick] = useState<number | null>(null);
  const [labelTitle, setLabelTitle] = useState('');
  const [labelNote, setLabelNote] = useState('');
  const [labelTags, setLabelTags] = useState('');

  const bounds = useMemo(() => boundsForFrames(frames), [frames]);
  const players = useMemo(() => interpolatePlayers(frames, currentTick), [frames, currentTick]);
  const visibleEvents = useMemo(() => recentEvents(events, currentTick, tickRate), [events, currentTick, tickRate]);
  const labels = labelState.key === storageKey ? labelState.labels : [];

  useEffect(() => {
    setCurrentTick(startTick);
    setPlaying(false);
  }, [parsed.demoId, parsed.sha256, startTick]);

  useEffect(() => {
    setLabelState({ key: storageKey, labels: readLabels(storageKey) });
  }, [storageKey]);

  useEffect(() => {
    if (!playing) return undefined;
    let raf = 0;
    let last = performance.now();
    const loop = (now: number) => {
      const dt = (now - last) / 1000;
      last = now;
      setCurrentTick((tick) => {
        const next = tick + dt * tickRate;
        if (next >= endTick) {
          setPlaying(false);
          return endTick;
        }
        return next;
      });
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [playing, tickRate, endTick]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const parent = canvas.parentElement;
    const cssWidth = Math.max(520, parent?.clientWidth ?? 760);
    const cssHeight = 520;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(cssWidth * dpr);
    canvas.height = Math.round(cssHeight * dpr);
    canvas.style.width = '100%';
    canvas.style.height = `${cssHeight}px`;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssWidth, cssHeight);
    ctx.fillStyle = '#050913';
    ctx.fillRect(0, 0, cssWidth, cssHeight);

    const pad = 32;
    const spanX = Math.max(1, bounds.maxX - bounds.minX);
    const spanY = Math.max(1, bounds.maxY - bounds.minY);
    const scale = Math.min((cssWidth - pad * 2) / spanX, (cssHeight - pad * 2) / spanY);
    const offsetX = (cssWidth - spanX * scale) / 2;
    const offsetY = (cssHeight - spanY * scale) / 2;
    const toScreen = (x: number, y: number) => ({
      x: offsetX + (x - bounds.minX) * scale,
      y: cssHeight - (offsetY + (y - bounds.minY) * scale),
    });

    ctx.strokeStyle = 'rgba(148, 163, 184, 0.08)';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 8; i += 1) {
      const x = offsetX + (spanX * scale * i) / 8;
      const y = offsetY + (spanY * scale * i) / 8;
      ctx.beginPath();
      ctx.moveTo(x, offsetY);
      ctx.lineTo(x, offsetY + spanY * scale);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(offsetX, y);
      ctx.lineTo(offsetX + spanX * scale, y);
      ctx.stroke();
    }

    ctx.strokeStyle = 'rgba(96, 165, 250, 0.22)';
    ctx.strokeRect(offsetX, offsetY, spanX * scale, spanY * scale);

    ctx.font = '12px Inter, system-ui, sans-serif';
    ctx.fillStyle = '#64748b';
    ctx.fillText(`${parsed.mapName ?? 'unknown map'} · ${players.length} players`, 18, 24);
    ctx.fillText(`tick ${Math.round(currentTick)} · ${formatTimeFromTick(currentTick, startTick, tickRate)}`, 18, 42);

    for (const player of players) drawPlayer(ctx, player, toScreen(player.x, player.y));

    if (visibleEvents.length > 0) {
      const boxWidth = 240;
      const boxHeight = 26 + visibleEvents.length * 18;
      ctx.fillStyle = 'rgba(8, 13, 25, 0.78)';
      ctx.strokeStyle = 'rgba(148, 163, 184, 0.12)';
      ctx.beginPath();
      ctx.roundRect(cssWidth - boxWidth - 16, 16, boxWidth, boxHeight, 8);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = '#94a3b8';
      ctx.font = '11px Inter, system-ui, sans-serif';
      ctx.fillText('Nearby events', cssWidth - boxWidth, 36);
      visibleEvents.forEach((event, index) => {
        ctx.fillStyle = index === 0 ? '#fbbf24' : '#64748b';
        ctx.fillText(`${formatTimeFromTick(event.tick, startTick, tickRate)}  ${event.type}`, cssWidth - boxWidth, 58 + index * 18);
      });
    }
  }, [bounds, currentTick, events, parsed.mapName, players, startTick, tickRate, visibleEvents]);

  function seekToTick(tick: number) {
    setCurrentTick(clamp(tick, startTick, endTick));
  }

  function saveLabel() {
    const rawStart = labelStartTick ?? currentTick;
    const label: DemoLabel = {
      id: newLabelId(),
      demoId: parsed.demoId ?? parsed.sha256,
      startTick: Math.round(Math.min(rawStart, currentTick)),
      endTick: Math.round(Math.max(rawStart, currentTick)),
      title: labelTitle.trim() || `Review label ${labels.length + 1}`,
      note: labelNote.trim() || undefined,
      tags: labelTags.split(',').map((tag) => tag.trim()).filter(Boolean),
      createdAt: new Date().toISOString(),
    };
    const next = [label, ...labels].sort((a, b) => a.startTick - b.startTick);
    setLabelState({ key: storageKey, labels: next });
    writeLabels(storageKey, next);
    setLabelStartTick(null);
    setLabelTitle('');
    setLabelNote('');
    setLabelTags('');
  }

  function deleteLabel(id: string) {
    const next = labels.filter((label) => label.id !== id);
    setLabelState({ key: storageKey, labels: next });
    writeLabels(storageKey, next);
  }

  if (frames.length === 0) {
    return (
      <section className="panel demo-review-panel">
        <div className="panel-head"><h2>Demo Review</h2></div>
        <p className="panel-placeholder">This demo parsed, but no tactical playback frames were produced. Try a different `.dem` file or check the parser error below.</p>
        {parsed.error && <pre className="demo-error">{parsed.error}</pre>}
      </section>
    );
  }

  return (
    <section className="panel demo-review-panel">
      <div className="panel-head demo-review-head">
        <div>
          <h2>{parsed.mapName ?? 'Demo Review'}</h2>
          <p className="demo-subtitle">Native 2D playback · {frames.length.toLocaleString()} frames · {events.length.toLocaleString()} events</p>
        </div>
        <div className="demo-clock">{formatTimeFromTick(currentTick, startTick, tickRate)} · tick {Math.round(currentTick)}</div>
      </div>
      <div className="demo-review-grid">
        <div className="demo-review-main">
          <canvas ref={canvasRef} className="demo-canvas" />
          <div className="demo-controls">
            <button className="primary" onClick={() => setPlaying(!playing)}>{playing ? 'Pause' : 'Play'}</button>
            <button onClick={() => { setPlaying(false); seekToTick(startTick); }}>Restart</button>
            <button onClick={() => setLabelStartTick(Math.round(currentTick))}>Mark start</button>
            <button disabled={labelStartTick === null && !labelTitle.trim()} onClick={saveLabel}>Save label end</button>
          </div>
          <input
            className="demo-timeline-input"
            type="range"
            min={startTick}
            max={endTick}
            step={1}
            value={Math.round(currentTick)}
            onChange={(event) => { setPlaying(false); seekToTick(Number(event.currentTarget.value)); }}
          />
          <div className="demo-timeline-meta">
            <span>{formatTimeFromTick(startTick, startTick, tickRate)}</span>
            <span>{labelStartTick !== null ? `label start: tick ${labelStartTick}` : 'select a start/end range to save a review moment'}</span>
            <span>{formatTimeFromTick(endTick, startTick, tickRate)}</span>
          </div>
        </div>
        <aside className="demo-review-sidebar">
          <div className="demo-label-form">
            <h3>Label moment</h3>
            <input value={labelTitle} placeholder="Title, e.g. B hold mistake" onChange={(event) => setLabelTitle(event.currentTarget.value)} />
            <textarea value={labelNote} placeholder="Notes for review" rows={3} onChange={(event) => setLabelNote(event.currentTarget.value)} />
            <input value={labelTags} placeholder="Tags: rotate, spacing, utility" onChange={(event) => setLabelTags(event.currentTarget.value)} />
          </div>
          <div className="demo-label-list">
            <h3>Labels</h3>
            {labels.length === 0 && <div className="empty">No labels yet. Mark a start, seek/play, then save the end.</div>}
            {labels.map((label) => (
              <div key={label.id} className="demo-label-row">
                <button className="demo-label-jump" onClick={() => { setPlaying(false); seekToTick(label.startTick); }}>
                  <b>{label.title}</b>
                  <span>{formatTimeFromTick(label.startTick, startTick, tickRate)}–{formatTimeFromTick(label.endTick, startTick, tickRate)}</span>
                  {label.tags.length > 0 && <em>{label.tags.join(' · ')}</em>}
                  {label.note && <small>{label.note}</small>}
                </button>
                <button className="demo-label-delete" title="Delete label" onClick={() => deleteLabel(label.id)}>×</button>
              </div>
            ))}
          </div>
        </aside>
      </div>
    </section>
  );
}
