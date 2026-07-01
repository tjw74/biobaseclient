import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import QRCode from 'qrcode';
import { frameAt } from '../../shared/mockTimeline';
import { buildLiveFrame, DEFAULT_API_BASE_URL, DEFAULT_CONNECT } from '../../shared/liveFrame';
import type { LiveMovementStatus, LiveServerStatus } from '../../shared/liveTypes';
import type { ClientSettings, LocalDemoFile, ParsedDemoSummary, PlaybackState, TimelineFrame, UploadQueueItem } from '../../shared/types';
import type { UpdateStatus } from '../../shared/updateTypes';
import { formatVersionClickFeedback } from '../../shared/updateFeedback';
import { DemoReviewPlayer } from './components/DemoReviewPlayer';
import './styles.css';

declare const __APP_VERSION__: string;

type Section = 'live' | 'shadow' | 'replay' | 'profile' | 'insights';

const isOverlayRoute = window.location.hash.includes('overlay');
if (isOverlayRoute) {
  document.documentElement.classList.add('overlay-mode');
}

/* ── Shared atoms ── */

function Key({ label, active }: { label: string; active: boolean }) {
  return <span className={active ? 'key active' : 'key'}>{label}</span>;
}

function StatCell({ label, value, accent }: { label: string; value: string | number; accent?: boolean }) {
  return (
    <div className={`stat-cell${accent ? ' accent' : ''}`}>
      <b>{value}</b>
      <span>{label}</span>
    </div>
  );
}

function Badge({ status }: { status: 'live' | 'soon' | 'idle' | 'online' | 'offline' }) {
  const label = status === 'live' ? 'live' : status === 'online' ? 'online' : status === 'soon' ? 'soon' : status === 'offline' ? 'offline' : 'waiting';
  return <span className={`badge badge--${status}`}>{label}</span>;
}

/* ── Nav icons ── */

function NavIcon({ id }: { id: string }) {
  const d: Record<string, string> = {
    live: 'M22 12h-4l-3 9L9 3l-3 9H2',
    shadow: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
    replay: 'M1 4v6h6M3.51 15a9 9 0 1 0 2.13-9.36L1 10',
    profile: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
    insights: 'M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5',
  };
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d={d[id] ?? ''} />
    </svg>
  );
}

/* ── Sidebar ── */

const NAV_ITEMS: { id: Section; label: string }[] = [
  { id: 'live', label: 'Live Dashboard' },
  { id: 'shadow', label: 'Shadow' },
  { id: 'replay', label: 'Replay' },
  { id: 'profile', label: 'Player Profile' },
  { id: 'insights', label: 'Insights' },
];

const SECTION_TITLES: Record<Section, [string, string]> = {
  live: ['LIVE DASHBOARD', 'Live Dashboard'],
  shadow: ['SHADOW', 'Shadow'],
  replay: ['REPLAY', 'Replay'],
  profile: ['PLAYER PROFILE', 'Player Profile'],
  insights: ['INSIGHTS', 'Insights'],
};

function Sidebar({ section, onNav, statusClass }: { section: Section; onNav: (s: Section) => void; statusClass: string }) {
  const [collapsed, setCollapsed] = useState(false);
  return (
    <aside className={`sidebar${collapsed ? ' collapsed' : ''}`}>
      <div className="sidebar-brand">
        <span className="sidebar-logo">⌘</span>
        {!collapsed && (
          <div className="sidebar-title">
            <span className="sidebar-name">BIOBASE</span>
            <span className="sidebar-sub">Performance Lab</span>
          </div>
        )}
        <button className="sidebar-collapse" onClick={() => setCollapsed(!collapsed)}>{collapsed ? '»' : '«'}</button>
      </div>
      <nav className="sidebar-nav">
        {NAV_ITEMS.map((item) => (
          <button
            key={item.id}
            className={`sidebar-item${section === item.id ? ' active' : ''}`}
            onClick={() => onNav(item.id)}
          >
            <NavIcon id={item.id} />
            {!collapsed && <span>{item.label}</span>}
          </button>
        ))}
      </nav>
      <div className="sidebar-footer">
        <span className={`pill-dot ${statusClass}`} />
        {!collapsed && <span className="sidebar-status">{statusClass === 'live' ? 'Live' : statusClass === 'online' ? 'Ready' : 'Offline'}</span>}
      </div>
    </aside>
  );
}

/* ── Section header ── */

function SectionHeader({ section, children }: { section: Section; children?: React.ReactNode }) {
  const [label, title] = SECTION_TITLES[section];
  return (
    <div className="section-header">
      <div>
        <span className="section-label">{label}</span>
        <h1 className="section-title">{title}</h1>
      </div>
      {children && <div className="section-actions">{children}</div>}
    </div>
  );
}

/* ── Version / update ── */

function VersionTag({ onStatus }: { onStatus?: (message: string) => void }) {
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState('');

  function showFeedback(message: string) {
    setFeedback(message);
    onStatus?.(message);
  }

  async function handleClick() {
    if (busy) return;
    if (!window.biobaseDesktop?.triggerUpdate) {
      showFeedback('Update check unavailable in this build');
      return;
    }
    setBusy(true);
    showFeedback('Checking for updates…');
    try {
      const status = await window.biobaseDesktop.triggerUpdate();
      showFeedback(formatVersionClickFeedback(status));
    } catch {
      showFeedback('Update check failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="version-check">
      <button
        type="button"
        className={`version-tag${busy ? ' busy' : ''}`}
        title={feedback || 'Check for updates'}
        disabled={busy}
        onClick={() => { void handleClick(); }}
      >
        v{__APP_VERSION__}
      </button>
      {feedback ? <span className="version-feedback" role="status" aria-live="polite">{feedback}</span> : null}
    </div>
  );
}

function UpdateBanner() {
  const [update, setUpdate] = useState<UpdateStatus>({ currentVersion: __APP_VERSION__, state: 'idle' });
  useEffect(() => {
    window.biobaseDesktop?.getUpdateStatus().then(setUpdate).catch(() => undefined);
    return window.biobaseDesktop?.onUpdateStatus((status) => setUpdate(status));
  }, []);
  if (update.state === 'idle' || update.state === 'not-available') return null;
  const ready = update.state === 'ready';
  const downloading = update.state === 'downloading' || update.state === 'available' || update.state === 'checking';
  const errored = update.state === 'error';
  return (
    <div className={`update-banner${ready ? ' ready' : ''}${errored ? ' error' : ''}`}>
      {downloading && (<><span>{update.message ?? 'Updating…'}</span><div className="update-progress"><span style={{ width: `${Math.round(update.progress ?? 0)}%` }} /></div></>)}
      {ready && <span>v{update.latestVersion} ready — restart to apply</span>}
      {errored && <span>{update.message ?? 'Update failed — will retry on next launch'}</span>}
      {ready && <button className="primary" onClick={() => { void window.biobaseDesktop?.installUpdate(); }}>Restart now</button>}
      {errored && <button onClick={() => { void window.biobaseDesktop?.checkForUpdates(); }}>Retry</button>}
    </div>
  );
}

/* ── Movement panel ── */

function MovementPanel({ frame, live }: { frame: TimelineFrame; live: boolean }) {
  const m = frame.movement;
  return (
    <section className="panel movement-hero">
      <div className="panel-head">
        <h2>Movement</h2>
        <Badge status={live ? 'live' : 'idle'} />
      </div>
      <div className="stat-grid stat-grid--hero">
        <StatCell label="speed" value={m.speed} accent={m.speed > 200} />
        <StatCell label="counter-strafe" value={m.counterStrafeScore.toFixed(2)} />
        <StatCell label="path efficiency" value={m.pathEfficiency.toFixed(2)} />
        <StatCell label="tick" value={frame.currentTick} />
      </div>
      <div className="keys-row keys-row--hero">
        <Key label="W" active={m.keys.w} />
        <Key label="A" active={m.keys.a} />
        <Key label="S" active={m.keys.s} />
        <Key label="D" active={m.keys.d} />
        <Key label="JUMP" active={m.keys.jump} />
        <Key label="DUCK" active={m.keys.crouch} />
      </div>
    </section>
  );
}

function ShootingPanel() {
  return (
    <section className="panel">
      <div className="panel-head">
        <h2>Shooting</h2>
        <Badge status="soon" />
      </div>
      <p className="panel-placeholder">Accuracy, spray control, and crosshair placement — coming in a future update.</p>
    </section>
  );
}

/* ── Shadow section (placeholder) ── */

function ShadowSection({ frame, live }: { frame: TimelineFrame; live: boolean }) {
  const m = frame.movement;
  return (
    <div className="live-stack">
      <section className="panel">
        <div className="panel-head">
          <h2>Performance Comparison</h2>
          <Badge status={live ? 'live' : 'idle'} />
        </div>
        <p className="panel-hint">Compare your real-time stats against benchmarks. Shadow mode adapts to your averages and highlights where you can improve.</p>
        <div className="shadow-grid">
          <div className="shadow-col">
            <h3 className="shadow-col-label">Your Stats</h3>
            <div className="stat-grid">
              <StatCell label="speed" value={m.speed} />
              <StatCell label="counter-strafe" value={m.counterStrafeScore.toFixed(2)} />
              <StatCell label="path efficiency" value={m.pathEfficiency.toFixed(2)} />
              <StatCell label="tick" value={frame.currentTick} />
            </div>
          </div>
          <div className="shadow-col">
            <h3 className="shadow-col-label">Benchmark</h3>
            <div className="stat-grid">
              <StatCell label="speed" value={245} accent />
              <StatCell label="counter-strafe" value="0.92" accent />
              <StatCell label="path efficiency" value="0.88" accent />
              <StatCell label="target" value="—" />
            </div>
          </div>
        </div>
      </section>
      <section className="panel">
        <div className="panel-head"><h2>Shadow Modes</h2></div>
        <div className="shadow-modes">
          <div className="shadow-mode active">
            <b>Personal Average</b>
            <span>Compare against your own rolling average</span>
          </div>
          <div className="shadow-mode">
            <b>Pro Benchmark</b>
            <span>Compare against shared pro player profiles</span>
          </div>
          <div className="shadow-mode">
            <b>Custom Threshold</b>
            <span>Set your own target values to train against</span>
          </div>
        </div>
      </section>
    </div>
  );
}

/* ── Player Profile section (placeholder) ── */

function PlayerProfileSection() {
  return (
    <div className="live-stack">
      <section className="panel">
        <div className="panel-head"><h2>Performance Scores</h2></div>
        <div className="stat-grid stat-grid--hero">
          <div className="stat-cell score-card">
            <span className="score-label">MOVEMENT QUALITY</span>
            <b>—</b>
            <span>Play a session to establish baseline</span>
          </div>
          <div className="stat-cell score-card">
            <span className="score-label">COUNTER-STRAFE</span>
            <b>—</b>
            <span>Stop accuracy and timing</span>
          </div>
          <div className="stat-cell score-card">
            <span className="score-label">PATH EFFICIENCY</span>
            <b>—</b>
            <span>Route optimization score</span>
          </div>
        </div>
      </section>
      <section className="panel">
        <div className="panel-head"><h2>Session History</h2></div>
        <p className="panel-placeholder">Your performance trends will appear here after you play sessions on Biobase.</p>
      </section>
    </div>
  );
}

/* ── Insights section (placeholder) ── */

function InsightsSection() {
  return (
    <div className="live-stack">
      <section className="panel">
        <div className="panel-head"><h2>Immediate</h2></div>
        <p className="panel-placeholder">Play a few sessions to generate movement insights and recommendations.</p>
      </section>
      <section className="panel">
        <div className="panel-head"><h2>Trends</h2></div>
        <p className="panel-placeholder">Long-term performance patterns will appear here as your profile builds.</p>
      </section>
    </div>
  );
}

/* ── Server pill (top bar compact + dropdown) ── */

function ServerPill({ status, trackedPlayer, onPickPlayer, onLaunchCs2, launchBusy, statusClass }: {
  status: LiveServerStatus | null;
  trackedPlayer: string;
  onPickPlayer: (name: string) => void;
  onLaunchCs2: () => void;
  launchBusy: boolean;
  statusClass: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const players = status?.players ?? [];
  const humans = players.filter((p) => p.steamid && p.steamid !== 'BOT');
  const bots = players.length - humans.length;
  const mapName = status?.map ?? 'offline';
  const isOnline = status?.ok ?? false;

  return (
    <div className="pill-wrap" ref={ref}>
      <button className={`header-pill${isOnline ? ' pill--online' : ' pill--offline'}`} onClick={() => setOpen(!open)}>
        <span className={`pill-dot ${statusClass}`} />
        <span className="pill-label">{isOnline ? mapName : 'Not connected'}</span>
        <span className="pill-arrow">{open ? '▴' : '▾'}</span>
      </button>
      {open && (
        <div className="dropdown">
          <div className="dropdown-section">
            <div className="dropdown-row-between">
              <span className="dropdown-label">Server</span>
              <Badge status={isOnline ? 'online' : 'offline'} />
            </div>
            <div className="dropdown-meta">
              <span className="meta-map">{mapName}</span>
              {isOnline && (
                <span className="meta-count">
                  {humans.length} player{humans.length !== 1 ? 's' : ''}
                  {bots > 0 ? ` · ${bots} bot${bots !== 1 ? 's' : ''}` : ''}
                </span>
              )}
            </div>
          </div>
          {humans.length > 0 && (
            <div className="dropdown-section">
              <span className="dropdown-label">Players — click to track</span>
              <div className="dropdown-players">
                {humans.map((p) => (
                  <button
                    key={`${p.userid}-${p.name}`}
                    type="button"
                    className={`player-row${trackedPlayer === p.name ? ' selected' : ''}`}
                    onClick={() => { onPickPlayer(p.name); setOpen(false); }}
                  >
                    <span>{p.name}</span>
                    <em>{p.ping}ms</em>
                  </button>
                ))}
              </div>
            </div>
          )}
          {humans.length === 0 && <p className="dropdown-empty">No players on server.</p>}
          <div className="dropdown-section dropdown-footer">
            <button className="launch-btn" disabled={launchBusy} onClick={() => { onLaunchCs2(); setOpen(false); }}>
              {launchBusy ? 'Connecting…' : 'Connect to Server'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── App menu (⋯) ── */

function AppMenu({ onStatus, overlayOn, overlayDisabled, onToggleOverlay, isWindows }: {
  onStatus: (msg: string) => void;
  overlayOn: boolean;
  overlayDisabled: boolean;
  onToggleOverlay: () => void;
  isWindows: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [companionUrl, setCompanionUrl] = useState('');
  const [qrDataUrl, setQrDataUrl] = useState('');
  const [busy, setBusy] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  async function createSideView() {
    setBusy(true);
    try {
      const result = await window.biobaseDesktop?.createCompanionLink();
      if (!result?.ok || !result.url) { onStatus(result?.error ?? 'Could not create SideView link'); return; }
      setCompanionUrl(result.url);
      const dataUrl = await QRCode.toDataURL(result.url, { margin: 1, width: 200, color: { dark: '#e2e8f0', light: '#00000000' } });
      setQrDataUrl(dataUrl);
      onStatus('SideView ready');
    } finally { setBusy(false); }
  }

  async function copySideViewLink() {
    if (!companionUrl) return;
    try { await navigator.clipboard.writeText(companionUrl); onStatus('SideView link copied'); } catch { onStatus(companionUrl); }
  }

  function handleOpen() {
    const willOpen = !open;
    setOpen(willOpen);
    if (willOpen && !qrDataUrl) void createSideView();
  }

  return (
    <div className="pill-wrap" ref={ref}>
      <button className="header-pill menu-trigger" onClick={handleOpen} title="Menu">⋯</button>
      {open && (
        <div className="dropdown app-menu">
          <div className="dropdown-section">
            <span className="dropdown-label">SideView</span>
            <p className="dropdown-hint">Open stats on another screen</p>
          </div>
          {busy && <p className="dropdown-hint" style={{ textAlign: 'center' }}>Generating…</p>}
          {qrDataUrl && (
            <div className="companion-qr-section">
              <img className="companion-qr" src={qrDataUrl} alt="SideView QR" />
            </div>
          )}
          <div className="dropdown-section dropdown-footer">
            <div className="companion-actions">
              <button type="button" disabled={busy} onClick={() => { void createSideView(); }}>
                {busy ? 'Creating…' : 'New QR'}
              </button>
              <button type="button" disabled={!companionUrl} onClick={() => { void copySideViewLink(); }}>
                Copy link
              </button>
            </div>
          </div>
          {isWindows && (
            <div className="dropdown-section">
              <div className="menu-toggle-row">
                <div>
                  <span className="dropdown-label">Game HUD</span>
                  <p className="dropdown-hint">Show stats overlay in CS2</p>
                </div>
                <label className="toggle">
                  <input type="checkbox" checked={overlayOn} disabled={overlayDisabled} onChange={onToggleOverlay} />
                  <span className="toggle-ui" />
                </label>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/* ── Overlay HUD (separate route) ── */

function OverlayRoute() {
  const [liveStatus, setLiveStatus] = useState<LiveServerStatus | null>(null);
  const [liveMovement, setLiveMovement] = useState<LiveMovementStatus | null>(null);
  useEffect(() => {
    let active = true;
    const tick = async () => {
      try {
        const [status, movement] = await Promise.all([window.biobaseDesktop?.getLiveStatus(), window.biobaseDesktop?.getLiveMovement()]);
        if (status) setLiveStatus(status);
        if (movement) setLiveMovement(movement);
      } catch { /* overlay preview */ }
      if (active) window.setTimeout(tick, 200);
    };
    tick();
    return () => { active = false; };
  }, []);
  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); void window.biobaseDesktop?.hideOverlay(); } };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);
  const tracked = liveMovement?.tracked ?? liveMovement?.samples?.[0] ?? null;
  const frame = useMemo(() => buildLiveFrame(liveStatus, tracked), [liveStatus, tracked]);
  const live = Boolean(liveMovement?.ok);
  return (
    <main className="overlay-stage">
      <div className="hud-card">
        <MovementPanel frame={frame} live={live} />
        <div className="hud-hint">Ctrl+Shift+M free mouse · Ctrl+Shift+O toggle · Esc hide</div>
      </div>
    </main>
  );
}

/* ── Replay tab ── */

function usePlaybackClock(): TimelineFrame {
  const [timeSec, setTimeSec] = useState(18);
  useEffect(() => {
    let live = true;
    const tick = async () => {
      try { const state = await window.biobaseDesktop?.getPlayback(); if (state) setTimeSec(state.currentTimeSec); } catch { /* browser preview */ }
      if (live) window.setTimeout(tick, 250);
    };
    tick();
    return () => { live = false; };
  }, []);
  return useMemo(() => frameAt(timeSec), [timeSec]);
}

function frameFromParsed(parsed: ParsedDemoSummary | null, timeSec: number): TimelineFrame {
  if (!parsed || parsed.movementSamples.length === 0) return frameAt(timeSec);
  const sample = parsed.movementSamples.reduce(
    (best, c) => (Math.abs(c.timeSec - timeSec) < Math.abs(best.timeSec - timeSec) ? c : best),
    parsed.movementSamples[0],
  );
  const frame = frameAt(timeSec);
  return { ...frame, currentTick: sample.tick, movement: { ...frame.movement, tick: sample.tick, timeSec: sample.timeSec, steamid: sample.steamid, name: sample.name, speed: sample.speed, counterStrafeScore: sample.counterStrafeScore, pathEfficiency: sample.pathEfficiency, x: sample.x, y: sample.y, z: sample.z } };
}

function ReplayRoute(props: {
  demos: LocalDemoFile[]; selected: LocalDemoFile | null; setSelected: React.Dispatch<React.SetStateAction<LocalDemoFile | null>>;
  parsed: ParsedDemoSummary | null; busy: boolean; playback: PlaybackState | null; queue: UploadQueueItem[];
  syncStatus: string; chooseDemo: () => Promise<void>; parseSelectedDemo: () => Promise<void>;
  uploadSummary: () => Promise<void>; seek: (d: number) => Promise<void>; togglePlayback: () => Promise<void>;
}) {
  const base = usePlaybackClock();
  const frame = frameFromParsed(props.parsed, props.playback?.currentTimeSec ?? base.currentTimeSec);
  const hasNativePlayback = Boolean(props.parsed?.frames?.length);
  return (
    <>
      <section className="panel">
        <div className="panel-head">
          <h2>Local Demos</h2>
          <div className="panel-actions">
            <button onClick={() => { void props.chooseDemo(); }}>Import .dem</button>
            <button className="primary" disabled={!props.selected || props.busy} onClick={() => { void props.parseSelectedDemo(); }}>
              {props.busy ? 'Parsing…' : 'Parse selected'}
            </button>
            <button disabled={!props.parsed || props.busy} onClick={() => { void props.uploadSummary(); }}>Upload summary</button>
          </div>
        </div>
        <div className="demo-list">
          {props.demos.length === 0 && <div className="empty">No demos auto-detected. Import a `.dem` file to review it inside BioBase.</div>}
          {props.demos.map((d) => <button key={d.path} className={props.selected?.path === d.path ? 'demo-row selected' : 'demo-row'} onClick={() => props.setSelected(d)}><span>{d.name}</span><em>{(d.bytes / 1024 / 1024).toFixed(1)} MB · {d.source}</em></button>)}
        </div>
      </section>
      {hasNativePlayback && props.parsed ? (
        <DemoReviewPlayer parsed={props.parsed} />
      ) : (
        <>
          <MovementPanel frame={frame} live={false} />
          <section className="panel">
            <div className="panel-head"><h2>Timeline</h2></div>
            <div className="timeline-bar"><span style={{ width: `${Math.min(100, ((props.playback?.currentTimeSec ?? 0) / (props.parsed?.durationSec || 120)) * 100)}%` }} /></div>
            <div className="timeline-meta">{(props.playback?.currentTimeSec ?? frame.currentTimeSec).toFixed(2)}s · tick {frame.currentTick}</div>
          </section>
        </>
      )}
      <section className="panel">
        <div className="panel-head"><h2>Upload Queue</h2></div>
        <div className="queue-list">
          {props.queue.length === 0 && <div className="empty">No uploads queued yet.</div>}
          {props.queue.slice(0, 8).map((item) => <div key={item.id} className={`queue-row ${item.status}`}><span>{item.demoName}</span><em>{item.status}{item.lastError ? ` · ${item.lastError}` : ''}</em></div>)}
        </div>
      </section>
      <p className="hint-line">Sync: {props.syncStatus} · Parser: {props.parsed?.parser ?? 'not run'} · Frames: {props.parsed?.frames?.length ?? 0} · Samples: {props.parsed?.movementSamples.length ?? 0}</p>
    </>
  );
}

/* ── Main dashboard ── */

function DashboardRoute() {
  const [section, setSection] = useState<Section>('live');
  const [demos, setDemos] = useState<LocalDemoFile[]>([]);
  const [selected, setSelected] = useState<LocalDemoFile | null>(null);
  const [parsed, setParsed] = useState<ParsedDemoSummary | null>(null);
  const [busy, setBusy] = useState(false);
  const [playback, setPlayback] = useState<PlaybackState | null>(null);
  const [settings, setSettings] = useState<ClientSettings>({ apiBaseUrl: DEFAULT_API_BASE_URL, deviceName: '', serverName: 'Biobase CS2' });
  const [queue, setQueue] = useState<UploadQueueItem[]>([]);
  const [syncStatus, setSyncStatus] = useState('not synced');
  const [pairingCode, setPairingCode] = useState('');
  const [liveStatus, setLiveStatus] = useState<LiveServerStatus | null>(null);
  const [liveMovement, setLiveMovement] = useState<LiveMovementStatus | null>(null);
  const [overlayKillSwitch, setOverlayKillSwitch] = useState(false);
  const [liveSessionBusy, setLiveSessionBusy] = useState(false);
  const [connectBusy, setConnectBusy] = useState(false);
  const [gameOverlayOn, setGameOverlayOn] = useState(false);
  const [platform, setPlatform] = useState<NodeJS.Platform>('win32');
  const isWindows = platform === 'win32';

  const connectTarget = useMemo(() => liveStatus?.connect ?? DEFAULT_CONNECT, [liveStatus?.connect]);

  async function connectToCs2Server() {
    const bridge = window.biobaseDesktop;
    if (!bridge) { setSyncStatus('Desktop bridge unavailable — restart Biobase Client'); return false; }
    setConnectBusy(true);
    try {
      const result = await bridge.connectCs2({ host: connectTarget.host, port: connectTarget.port });
      if (result.ok) { setSyncStatus(`Connecting to ${connectTarget.host}:${connectTarget.port}`); return true; }
      setSyncStatus(result.error);
      return false;
    } finally { setConnectBusy(false); }
  }

  useEffect(() => {
    let active = true;
    const pollStatus = async () => { try { const s = await window.biobaseDesktop?.getLiveStatus(); if (active) setLiveStatus(s ?? null); } catch { /* */ } };
    const pollMovement = async () => { try { const m = await window.biobaseDesktop?.getLiveMovement(); if (active) setLiveMovement(m ?? null); } catch { /* */ } };
    const pollOverlay = async () => { try { const v = await window.biobaseDesktop?.isOverlayVisible?.(); if (active) setGameOverlayOn(Boolean(v)); } catch { /* */ } };
    pollStatus(); pollMovement(); pollOverlay();
    const t1 = window.setInterval(pollStatus, 2000);
    const t2 = window.setInterval(pollMovement, 500);
    const t3 = window.setInterval(pollOverlay, 1000);
    window.biobaseDesktop?.scanDemos().then(setDemos).catch(() => setDemos([]));
    window.biobaseDesktop?.getSettings().then(setSettings).catch(() => undefined);
    window.biobaseDesktop?.getPlatform?.().then(setPlatform).catch(() => undefined);
    window.biobaseDesktop?.getUploadQueue().then(setQueue).catch(() => undefined);
    window.biobaseDesktop?.startLivePolling().catch(() => undefined);
    window.biobaseDesktop?.startMovementPolling().catch(() => undefined);
    window.biobaseDesktop?.isOverlayKillSwitch?.().then((b) => { if (active) setOverlayKillSwitch(Boolean(b)); }).catch(() => undefined);
    void connectToCs2Server();
    const heartbeat = () => { void window.biobaseDesktop?.sendMainHeartbeat?.(); };
    heartbeat();
    const t4 = window.setInterval(heartbeat, 15_000);
    const t5 = window.setInterval(() => window.biobaseDesktop?.getPlayback().then(setPlayback).catch(() => undefined), 500);
    return () => { active = false; [t1, t2, t3, t4, t5].forEach(clearInterval); };
  }, []);

  async function chooseDemo() { const f = await window.biobaseDesktop?.selectDemo(); if (!f) return; setSelected(f); setDemos((e) => (e.some((d) => d.path === f.path) ? e : [f, ...e])); }
  async function parseSelectedDemo() { if (!selected) return; setBusy(true); try { const r = await window.biobaseDesktop?.parseDemo(selected.path); if (r) setParsed(r); setSyncStatus(r.frames?.length ? 'demo playback ready' : 'parsed locally'); } finally { setBusy(false); } }
  async function seek(delta: number) { const c = playback?.currentTimeSec ?? 0; const s = await window.biobaseDesktop?.setPlayback({ currentTimeSec: Math.max(0, c + delta), playing: playback?.playing ?? false }); if (s) setPlayback(s); }
  async function togglePlayback() { const s = await window.biobaseDesktop?.setPlayback({ currentTimeSec: playback?.currentTimeSec ?? 0, playing: !playback?.playing }); if (s) setPlayback(s); }
  async function uploadSummary() { if (!parsed) return; setSyncStatus('uploading…'); const r = await window.biobaseDesktop?.uploadParsedSummary(parsed); if (!r) return; setQueue(r.queue); setSyncStatus(r.item.status === 'uploaded' ? 'uploaded' : r.item.lastError ?? r.item.status); }

  async function saveClientSettings() {
    const next = await window.biobaseDesktop?.saveSettings(settings);
    if (next) setSettings(next);
    setSyncStatus('settings saved');
    await window.biobaseDesktop?.startLivePolling();
    await window.biobaseDesktop?.startMovementPolling();
  }

  async function pairClientDevice() {
    setSyncStatus('pairing device…');
    const result = await window.biobaseDesktop?.pairDevice({ pairingCode });
    if (!result) return;
    setSettings(result.settings);
    setSyncStatus(result.ok ? 'device paired' : result.error ?? 'pairing failed');
  }

  async function toggleGameOverlay() {
    if (overlayKillSwitch) { setSyncStatus('Overlay blocked — remove BIOBASE_DISABLE_OVERLAY and restart'); return; }
    await window.biobaseDesktop?.toggleOverlay();
    const visible = await window.biobaseDesktop?.isOverlayVisible?.();
    setGameOverlayOn(Boolean(visible));
    setSyncStatus(visible ? 'Game overlay on' : 'Game overlay off');
  }

  async function launchCs2() {
    setLiveSessionBusy(true);
    try {
      const next = await window.biobaseDesktop?.saveSettings(settings);
      if (next) setSettings(next);
      await connectToCs2Server();
    } finally { setLiveSessionBusy(false); }
  }

  async function toggleShareStats(enabled: boolean) {
    const next = { ...settings, shareStatsOnServer: enabled };
    setSettings(next);
    const saved = await window.biobaseDesktop?.saveSettings(next);
    if (saved) setSettings(saved);
    setSyncStatus(enabled ? 'Stats sharing on' : 'Stats sharing off');
  }

  function pickPlayer(name: string) {
    const next = { ...settings, trackedPlayerName: name };
    setSettings(next);
    void saveClientSettings();
  }

  const movementLive = Boolean(liveMovement?.ok);
  const serverOnline = Boolean(liveStatus?.ok);
  const statusClass = movementLive ? 'live' : serverOnline ? 'online' : 'offline';
  const tracked = liveMovement?.tracked ?? liveMovement?.samples?.[0] ?? null;
  const liveFrame = useMemo(() => buildLiveFrame(liveStatus, tracked), [liveStatus, tracked]);

  return (
    <div className="app-shell">
      <Sidebar section={section} onNav={setSection} statusClass={statusClass} />
      <div className="app-content">
        <header className="content-header">
          <SectionHeader section={section}>
            <VersionTag onStatus={setSyncStatus} />
          </SectionHeader>
          <div className="content-header-right">
            <ServerPill
              status={liveStatus}
              trackedPlayer={settings.trackedPlayerName ?? ''}
              onPickPlayer={pickPlayer}
              onLaunchCs2={() => { void launchCs2(); }}
              launchBusy={liveSessionBusy || connectBusy}
              statusClass={statusClass}
            />
            <AppMenu
              onStatus={setSyncStatus}
              overlayOn={gameOverlayOn}
              overlayDisabled={overlayKillSwitch || liveSessionBusy}
              onToggleOverlay={() => { void toggleGameOverlay(); }}
              isWindows={isWindows}
            />
          </div>
        </header>
        <UpdateBanner />
        <main className="app-main">
          {section === 'live' && (
            <div className="live-stack">
              <MovementPanel frame={liveFrame} live={movementLive} />
              <ShootingPanel />
            </div>
          )}
          {section === 'shadow' && <ShadowSection frame={liveFrame} live={movementLive} />}
          {section === 'replay' && (
            <ReplayRoute
              demos={demos} selected={selected} setSelected={setSelected} parsed={parsed} busy={busy}
              playback={playback} queue={queue} syncStatus={syncStatus} chooseDemo={chooseDemo}
              parseSelectedDemo={parseSelectedDemo} uploadSummary={uploadSummary} seek={seek} togglePlayback={togglePlayback}
            />
          )}
          {section === 'profile' && <PlayerProfileSection />}
          {section === 'insights' && <InsightsSection />}
          <details className="advanced">
            <summary>Advanced</summary>
            <div className="advanced-grid">
              <input className="player-field" value={settings.trackedPlayerName ?? ''} placeholder="Track player by name" onChange={(e) => setSettings({ ...settings, trackedPlayerName: e.target.value })} onBlur={() => { void saveClientSettings(); }} />
              <label className="toggle">
                <input type="checkbox" checked={settings.shareStatsOnServer !== false} onChange={(e) => { void toggleShareStats(e.target.checked); }} />
                <span className="toggle-ui" />
                Share stats
              </label>
            </div>
            <div className="advanced-grid">
              <button onClick={() => { void connectToCs2Server(); }}>Connect to Server</button>
              <button onClick={() => { void window.biobaseDesktop?.releaseMouse?.(); }}>Release mouse (Ctrl+Shift+M)</button>
              <button onClick={() => { void window.biobaseDesktop?.createCs2Shortcut().then((r) => r && setSyncStatus(r.ok ? 'Desktop icon created' : r.error)); }}>Desktop Play icon</button>
            </div>
            <div className="advanced-grid">
              <input value={settings.deviceName} placeholder="Device name" onChange={(e) => setSettings({ ...settings, deviceName: e.target.value })} />
              <button onClick={saveClientSettings}>Save settings</button>
              <input value={pairingCode} placeholder="Pairing code" onChange={(e) => setPairingCode(e.target.value)} />
              <button disabled={!pairingCode.trim()} onClick={pairClientDevice}>Pair device</button>
            </div>
          </details>
          <footer className="status-bar">
            <span>{syncStatus}</span>
            <span>{liveStatus?.map ?? 'server offline'}</span>
            <span>{movementLive ? 'movement feed live' : 'ready'}</span>
          </footer>
        </main>
      </div>
    </div>
  );
}

function App() {
  return isOverlayRoute ? <OverlayRoute /> : <DashboardRoute />;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
