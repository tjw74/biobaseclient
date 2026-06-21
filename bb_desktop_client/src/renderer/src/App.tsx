import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import QRCode from 'qrcode';
import { frameAt } from '../../shared/mockTimeline';
import { buildLiveFrame, DEFAULT_API_BASE_URL, DEFAULT_CONNECT } from '../../shared/liveFrame';
import type { AppMode } from '../../shared/liveTypes';
import type { LiveMovementStatus, LiveServerStatus } from '../../shared/liveTypes';
import type { ClientSettings, LocalDemoFile, ParsedDemoSummary, PlaybackState, TimelineFrame, UploadQueueItem } from '../../shared/types';
import type { UpdateStatus } from '../../shared/updateTypes';
import './styles.css';

declare const __APP_VERSION__: string;

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

/* ── Version / update ── */

function VersionTag({ onStatus }: { onStatus?: (message: string) => void }) {
  const [busy, setBusy] = useState(false);
  async function handleClick() {
    if (busy || !window.biobaseDesktop?.triggerUpdate) return;
    setBusy(true);
    onStatus?.('Checking for updates…');
    try {
      const status = await window.biobaseDesktop.triggerUpdate();
      if (status.state === 'ready') { onStatus?.(`v${status.latestVersion ?? ''} ready — use Restart in banner`); return; }
      if (status.state === 'checking' || status.state === 'downloading' || status.state === 'available') { onStatus?.(status.message ?? 'Downloading update…'); return; }
      if (status.state === 'not-available') { onStatus?.('Already on the latest version'); return; }
      if (status.message?.includes('Mac download')) { onStatus?.('Opening Mac download in your browser…'); return; }
      if (status.state === 'error') { onStatus?.(status.message ?? 'Update check failed'); return; }
      onStatus?.('Update check started');
    } catch { onStatus?.('Update check failed'); } finally { setBusy(false); }
  }
  return (
    <button type="button" className={`version-tag${busy ? ' busy' : ''}`} title="Check for updates" disabled={busy} onClick={() => { void handleClick(); }}>
      v{__APP_VERSION__}
    </button>
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

/* ── Movement panel (hero) ── */

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

/* ── Server pill (top bar compact + dropdown) ── */

function ServerPill({ status, trackedPlayer, onPickPlayer, isWindows, onLaunchCs2, launchBusy }: {
  status: LiveServerStatus | null;
  trackedPlayer: string;
  onPickPlayer: (name: string) => void;
  isWindows: boolean;
  onLaunchCs2: () => void;
  launchBusy: boolean;
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
        <span className={`pill-dot ${isOnline ? 'online' : 'offline'}`} />
        <span className="pill-label">{mapName}</span>
        {isOnline && <span className="pill-sep">&middot;</span>}
        {isOnline && <span className="pill-count">{humans.length}</span>}
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
          {isWindows && (
            <div className="dropdown-section dropdown-footer">
              <button className="launch-btn" disabled={launchBusy} onClick={() => { onLaunchCs2(); setOpen(false); }}>
                {launchBusy ? 'Launching…' : 'Launch CS2 on Biobase'}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/* ── Companion button (top bar + popover) ── */

function CompanionButton({ onStatus }: { onStatus: (msg: string) => void }) {
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

  async function create() {
    setBusy(true);
    try {
      const result = await window.biobaseDesktop?.createCompanionLink();
      if (!result?.ok || !result.url) { onStatus(result?.error ?? 'Could not create companion link'); return; }
      setCompanionUrl(result.url);
      const dataUrl = await QRCode.toDataURL(result.url, { margin: 1, width: 200, color: { dark: '#eef2ff', light: '#00000000' } });
      setQrDataUrl(dataUrl);
      onStatus('Companion ready');
    } finally { setBusy(false); }
  }

  async function copy() {
    if (!companionUrl) return;
    try { await navigator.clipboard.writeText(companionUrl); onStatus('Companion link copied'); } catch { onStatus(companionUrl); }
  }

  function handleOpen() {
    const willOpen = !open;
    setOpen(willOpen);
    if (willOpen && !qrDataUrl) void create();
  }

  return (
    <div className="pill-wrap" ref={ref}>
      <button className={`header-pill pill--companion${qrDataUrl ? ' has-qr' : ''}`} onClick={handleOpen} title="Phone companion">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
          <rect x="5" y="2" width="14" height="20" rx="2" ry="2" />
          <line x1="12" y1="18" x2="12.01" y2="18" />
        </svg>
      </button>
      {open && (
        <div className="dropdown companion-dropdown">
          <div className="dropdown-section">
            <div className="dropdown-row-between">
              <span className="dropdown-label">Phone Companion</span>
              <button className="dropdown-close" onClick={() => setOpen(false)}>&times;</button>
            </div>
            <p className="dropdown-hint">Scan QR on your phone for live stats while you play.</p>
          </div>
          {busy && <p className="dropdown-hint" style={{ textAlign: 'center' }}>Generating...</p>}
          {qrDataUrl && (
            <div className="companion-qr-section">
              <img className="companion-qr" src={qrDataUrl} alt="Companion QR" />
            </div>
          )}
          <div className="dropdown-section dropdown-footer">
            <div className="companion-actions">
              <button type="button" disabled={busy} onClick={() => { void create(); }}>
                {busy ? 'Creating…' : 'New QR'}
              </button>
              <button type="button" disabled={!companionUrl} onClick={() => { void copy(); }}>
                Copy link
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── Overlay toggle (top bar) ── */

function OverlayToggle({ on, disabled, onToggle }: { on: boolean; disabled: boolean; onToggle: () => void }) {
  return (
    <button
      className={`header-pill pill--overlay${on ? ' on' : ''}`}
      disabled={disabled}
      onClick={onToggle}
      title={on ? 'Hide game overlay (Ctrl+Shift+O)' : 'Show game overlay (Ctrl+Shift+O)'}
    >
      <span className={`pill-dot ${on ? 'live' : ''}`} />
      Overlay
    </button>
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
        <div className="hud-hint">Ctrl+Shift+M free mouse &middot; Ctrl+Shift+O toggle &middot; Esc hide</div>
      </div>
    </main>
  );
}

/* ── Review tab ── */

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

function ReviewRoute(props: {
  demos: LocalDemoFile[]; selected: LocalDemoFile | null; setSelected: React.Dispatch<React.SetStateAction<LocalDemoFile | null>>;
  parsed: ParsedDemoSummary | null; busy: boolean; playback: PlaybackState | null; queue: UploadQueueItem[];
  syncStatus: string; chooseDemo: () => Promise<void>; parseSelectedDemo: () => Promise<void>;
  uploadSummary: () => Promise<void>; seek: (d: number) => Promise<void>; togglePlayback: () => Promise<void>;
}) {
  const base = usePlaybackClock();
  const frame = frameFromParsed(props.parsed, props.playback?.currentTimeSec ?? base.currentTimeSec);
  return (
    <>
      <MovementPanel frame={frame} live={false} />
      <section className="panel">
        <div className="panel-head"><h2>Local Demos</h2></div>
        <div className="demo-list">
          {props.demos.length === 0 && <div className="empty">No demos auto-detected. Use Import .dem in the sidebar.</div>}
          {props.demos.map((d) => <button key={d.path} className={props.selected?.path === d.path ? 'demo-row selected' : 'demo-row'} onClick={() => props.setSelected(d)}><span>{d.name}</span><em>{(d.bytes / 1024 / 1024).toFixed(1)} MB &middot; {d.source}</em></button>)}
        </div>
      </section>
      <section className="panel">
        <div className="panel-head"><h2>Timeline</h2></div>
        <div className="timeline-bar"><span style={{ width: `${Math.min(100, ((props.playback?.currentTimeSec ?? 0) / (props.parsed?.durationSec || 120)) * 100)}%` }} /></div>
        <div className="timeline-meta">{(props.playback?.currentTimeSec ?? frame.currentTimeSec).toFixed(2)}s &middot; tick {frame.currentTick}</div>
      </section>
      <section className="panel">
        <div className="panel-head"><h2>Upload Queue</h2></div>
        <div className="queue-list">
          {props.queue.length === 0 && <div className="empty">No uploads queued yet.</div>}
          {props.queue.slice(0, 8).map((item) => <div key={item.id} className={`queue-row ${item.status}`}><span>{item.demoName}</span><em>{item.status}{item.lastError ? ` · ${item.lastError}` : ''}</em></div>)}
        </div>
      </section>
      <p className="hint-line">Sync: {props.syncStatus} &middot; Parser: {props.parsed?.parser ?? 'not run'} &middot; Samples: {props.parsed?.movementSamples.length ?? 0}</p>
    </>
  );
}

/* ── Main dashboard ── */

function DashboardRoute() {
  const [appMode, setAppMode] = useState<AppMode>('live');
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
      if (result.ok) { setSyncStatus(`Launching CS2 → ${connectTarget.host}:${connectTarget.port}`); return true; }
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
    const heartbeat = () => { void window.biobaseDesktop?.sendMainHeartbeat?.(); };
    heartbeat();
    const t4 = window.setInterval(heartbeat, 15_000);
    const t5 = window.setInterval(() => window.biobaseDesktop?.getPlayback().then(setPlayback).catch(() => undefined), 500);
    return () => { active = false; [t1, t2, t3, t4, t5].forEach(clearInterval); };
  }, []);

  async function chooseDemo() { const f = await window.biobaseDesktop?.selectDemo(); if (!f) return; setSelected(f); setDemos((e) => (e.some((d) => d.path === f.path) ? e : [f, ...e])); }
  async function parseSelectedDemo() { if (!selected) return; setBusy(true); try { const r = await window.biobaseDesktop?.parseDemo(selected.path); if (r) setParsed(r); setSyncStatus('parsed locally'); } finally { setBusy(false); } }
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
      <header className="app-header">
        <div className="brand">Biobase <VersionTag onStatus={setSyncStatus} /></div>
        <nav className="nav-tabs">
          <button className={appMode === 'live' ? 'active' : ''} onClick={() => setAppMode('live')}>Live</button>
          <button className={appMode === 'review' ? 'active' : ''} onClick={() => setAppMode('review')}>Playback</button>
        </nav>
        <div className="header-spacer" />
        <ServerPill
          status={liveStatus}
          trackedPlayer={settings.trackedPlayerName ?? ''}
          onPickPlayer={pickPlayer}
          isWindows={isWindows}
          onLaunchCs2={() => { void launchCs2(); }}
          launchBusy={liveSessionBusy || connectBusy}
        />
        <CompanionButton onStatus={setSyncStatus} />
        {isWindows && (
          <OverlayToggle on={gameOverlayOn} disabled={overlayKillSwitch || liveSessionBusy} onToggle={() => { void toggleGameOverlay(); }} />
        )}
        <span className={`status-dot ${statusClass}`} title={movementLive ? 'Live' : serverOnline ? 'Server up' : 'Offline'} />
      </header>
      <UpdateBanner />
      <main className="app-main">
        <div className="app-main-inner">
          {appMode === 'live' && (
            <div className="live-stack">
              <MovementPanel frame={liveFrame} live={movementLive} />
              <ShootingPanel />
            </div>
          )}
          {appMode === 'review' && (
            <ReviewRoute
              demos={demos} selected={selected} setSelected={setSelected} parsed={parsed} busy={busy}
              playback={playback} queue={queue} syncStatus={syncStatus} chooseDemo={chooseDemo}
              parseSelectedDemo={parseSelectedDemo} uploadSummary={uploadSummary} seek={seek} togglePlayback={togglePlayback}
            />
          )}
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
              <button onClick={() => { void connectToCs2Server(); }}>Reconnect CS2</button>
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
        </div>
      </main>
    </div>
  );
}

function App() {
  return isOverlayRoute ? <OverlayRoute /> : <DashboardRoute />;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
