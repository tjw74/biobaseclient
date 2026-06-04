import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { frameAt } from '../../shared/mockTimeline';
import type { ClientSettings, LocalDemoFile, ParsedDemoSummary, PlaybackState, TimelineFrame, UploadQueueItem } from '../../shared/types';
import './styles.css';

function usePlaybackClock(): TimelineFrame {
  const [timeSec, setTimeSec] = useState(18);
  useEffect(() => {
    let live = true;
    const tick = async () => {
      try {
        const state = await window.biobaseDesktop?.getPlayback();
        if (state) setTimeSec(state.currentTimeSec);
      } catch {
        // The browser preview has no desktop bridge; keep mock timeline alive.
      }
      if (live) window.setTimeout(tick, 250);
    };
    tick();
    return () => {
      live = false;
    };
  }, []);
  return useMemo(() => frameAt(timeSec), [timeSec]);
}

function frameFromParsed(parsed: ParsedDemoSummary | null, timeSec: number): TimelineFrame {
  if (!parsed || parsed.movementSamples.length === 0) return frameAt(timeSec);
  const sample = parsed.movementSamples.reduce(
    (best, candidate) => (Math.abs(candidate.timeSec - timeSec) < Math.abs(best.timeSec - timeSec) ? candidate : best),
    parsed.movementSamples[0],
  );
  const frame = frameAt(timeSec);
  return {
    ...frame,
    currentTick: sample.tick,
    movement: {
      ...frame.movement,
      tick: sample.tick,
      timeSec: sample.timeSec,
      steamid: sample.steamid,
      name: sample.name,
      speed: sample.speed,
      counterStrafeScore: sample.counterStrafeScore,
      pathEfficiency: sample.pathEfficiency,
      x: sample.x,
      y: sample.y,
      z: sample.z,
    },
  };
}

function Key({ label, active }: { label: string; active: boolean }) {
  return <span className={active ? 'key active' : 'key'}>{label}</span>;
}

function Hud({ frame }: { frame: TimelineFrame }) {
  const movement = frame.movement;
  return (
    <div className="hud-card">
      <div className="hud-topline">
        <span>Biobase Movement</span>
        <span>{movement.name ?? frame.match.map}</span>
      </div>
      <div className="hud-grid">
        <div><b>{movement.speed}</b><span>speed</span></div>
        <div><b>{movement.counterStrafeScore.toFixed(2)}</b><span>counter</span></div>
        <div><b>{movement.pathEfficiency.toFixed(2)}</b><span>path</span></div>
        <div><b>{frame.currentTick}</b><span>tick</span></div>
      </div>
      <div className="keys">
        <Key label="W" active={movement.keys.w} />
        <Key label="A" active={movement.keys.a} />
        <Key label="S" active={movement.keys.s} />
        <Key label="D" active={movement.keys.d} />
        <Key label="J" active={movement.keys.jump} />
        <Key label="C" active={movement.keys.crouch} />
      </div>
    </div>
  );
}

function OverlayRoute() {
  const frame = usePlaybackClock();
  return <main className="overlay-stage"><Hud frame={frame} /></main>;
}

function Metric({ label, value, unit }: { label: string; value: string | number; unit: string }) {
  return <div className="metric"><span>{label}</span><b>{value}</b><em>{unit}</em></div>;
}

function DashboardRoute() {
  const [demos, setDemos] = useState<LocalDemoFile[]>([]);
  const [selected, setSelected] = useState<LocalDemoFile | null>(null);
  const [parsed, setParsed] = useState<ParsedDemoSummary | null>(null);
  const [busy, setBusy] = useState(false);
  const [playback, setPlayback] = useState<PlaybackState | null>(null);
  const [settings, setSettings] = useState<ClientSettings>({ apiBaseUrl: '', deviceName: '', serverName: 'Biobase CS2' });
  const [queue, setQueue] = useState<UploadQueueItem[]>([]);
  const [syncStatus, setSyncStatus] = useState('not synced');
  const [pairingCode, setPairingCode] = useState('');

  const base = usePlaybackClock();
  const frame = frameFromParsed(parsed, playback?.currentTimeSec ?? base.currentTimeSec);

  useEffect(() => {
    window.biobaseDesktop?.scanDemos().then(setDemos).catch(() => setDemos([]));
    window.biobaseDesktop?.getSettings().then(setSettings).catch(() => undefined);
    window.biobaseDesktop?.getUploadQueue().then(setQueue).catch(() => undefined);
    const timer = window.setInterval(() => window.biobaseDesktop?.getPlayback().then(setPlayback).catch(() => undefined), 500);
    return () => window.clearInterval(timer);
  }, []);

  async function chooseDemo() {
    const file = await window.biobaseDesktop?.selectDemo();
    if (!file) return;
    setSelected(file);
    setDemos((existing) => (existing.some((demo) => demo.path === file.path) ? existing : [file, ...existing]));
  }

  async function parseSelectedDemo() {
    if (!selected) return;
    setBusy(true);
    try {
      const result = await window.biobaseDesktop?.parseDemo(selected.path);
      if (result) setParsed(result);
      setSyncStatus('parsed locally');
    } finally {
      setBusy(false);
    }
  }

  async function seek(delta: number) {
    const current = playback?.currentTimeSec ?? 0;
    const state = await window.biobaseDesktop?.setPlayback({ currentTimeSec: Math.max(0, current + delta), playing: playback?.playing ?? false });
    if (state) setPlayback(state);
  }

  async function togglePlayback() {
    const state = await window.biobaseDesktop?.setPlayback({ currentTimeSec: playback?.currentTimeSec ?? 0, playing: !playback?.playing });
    if (state) setPlayback(state);
  }

  async function saveClientSettings() {
    const next = await window.biobaseDesktop?.saveSettings(settings);
    if (next) setSettings(next);
    setSyncStatus('settings saved');
  }

  async function pairClientDevice() {
    setSyncStatus('pairing device…');
    const result = await window.biobaseDesktop?.pairDevice({ pairingCode });
    if (!result) return;
    setSettings(result.settings);
    setSyncStatus(result.ok ? 'device paired' : result.error ?? 'pairing failed');
  }

  async function uploadSummary() {
    if (!parsed) return;
    setSyncStatus('uploading…');
    const result = await window.biobaseDesktop?.uploadParsedSummary(parsed);
    if (!result) return;
    setQueue(result.queue);
    setSyncStatus(result.item.status === 'uploaded' ? 'uploaded' : result.item.lastError ?? result.item.status);
  }

  async function retryQueue() {
    setSyncStatus('syncing queue…');
    const next = await window.biobaseDesktop?.syncUploadQueue();
    if (!next) return;
    setQueue(next);
    const failed = next.find((item) => item.status === 'failed');
    setSyncStatus(failed ? failed.lastError ?? 'failed' : 'queue synced');
  }

  const movement = frame.movement;
  return (
    <main className="app-shell">
      <aside className="side-panel">
        <div className="brand">Biobase</div>
        <button className="primary" onClick={() => window.biobaseDesktop?.showOverlay()}>Show HUD Overlay</button>
        <button onClick={() => window.biobaseDesktop?.hideOverlay()}>Hide HUD</button>
        <button onClick={chooseDemo}>Import .dem</button>
        <button disabled={!selected || busy} onClick={parseSelectedDemo}>{busy ? 'Parsing…' : 'Parse selected demo'}</button>
        <button disabled={!parsed} onClick={uploadSummary}>Upload summary</button>
        <button onClick={retryQueue}>Retry queue</button>
        <div className="section-label">Playback sync</div>
        <div className="button-row">
          <button onClick={() => seek(-5)}>-5s</button>
          <button onClick={togglePlayback}>{playback?.playing ? 'Pause' : 'Play'}</button>
          <button onClick={() => seek(5)}>+5s</button>
        </div>
        <div className="section-label">Settings</div>
        <input value={settings.apiBaseUrl} placeholder="https://biobase.example.com" onChange={(event) => setSettings({ ...settings, apiBaseUrl: event.target.value })} />
        <input value={settings.deviceName} placeholder="Device name" onChange={(event) => setSettings({ ...settings, deviceName: event.target.value })} />
        <input value={settings.serverName} placeholder="Server name" onChange={(event) => setSettings({ ...settings, serverName: event.target.value })} />
        <button onClick={saveClientSettings}>Save settings</button>
        <input value={pairingCode} placeholder="Pairing code" onChange={(event) => setPairingCode(event.target.value)} />
        <button disabled={!settings.apiBaseUrl || !pairingCode.trim()} onClick={pairClientDevice}>Pair device</button>
        <div className="status-list">
          <span>Parser: {parsed?.parser ?? 'not run'}</span>
          <span>Samples: {parsed?.movementSamples.length ?? 0}</span>
          <span>Players: {parsed?.players.length ?? 0}</span>
          <span>Central sync: {syncStatus}</span>
          <span>Device: {settings.deviceId ? `paired ${settings.deviceId.slice(0, 10)}…` : 'not paired'}</span>
          <span>Queue: {queue.filter((item) => item.status !== 'uploaded').length} pending / {queue.length} total</span>
          {parsed?.error && <span className="warn">Fallback: {parsed.error.slice(0, 80)}</span>}
        </div>
      </aside>
      <section className="content">
        <header className="page-header">
          <div><p className="eyebrow">Windows desktop client</p><h1>Movement Review</h1></div>
          <div className="match-pill">{selected?.name ?? 'No demo selected'}</div>
        </header>
        <section className="hero-grid">
          <div className="replay-panel"><div className="video-placeholder"><Hud frame={frame} /><span className="watermark">CS2 replay + transparent HUD target</span></div></div>
          <div className="metrics-panel">
            <Metric label="Speed" value={movement.speed} unit="u/s" />
            <Metric label="Counter-strafe" value={movement.counterStrafeScore.toFixed(2)} unit="score" />
            <Metric label="Path efficiency" value={movement.pathEfficiency.toFixed(2)} unit="score" />
            <Metric label="Timeline" value={(playback?.currentTimeSec ?? frame.currentTimeSec).toFixed(1)} unit="sec" />
          </div>
        </section>
        <section className="timeline-card">
          <div className="section-title">Local demos</div>
          <div className="demo-list">
            {demos.length === 0 && <div className="empty">No demos auto-detected. Use Import .dem.</div>}
            {demos.map((demo) => <button key={demo.path} className={selected?.path === demo.path ? 'demo-row selected' : 'demo-row'} onClick={() => setSelected(demo)}><span>{demo.name}</span><em>{(demo.bytes / 1024 / 1024).toFixed(1)} MB · {demo.source}</em></button>)}
          </div>
        </section>
        <section className="timeline-card">
          <div className="section-title">Timeline</div>
          <div className="timeline-bar"><span style={{ width: `${Math.min(100, ((playback?.currentTimeSec ?? 0) / (parsed?.durationSec || 120)) * 100)}%` }} /></div>
          <div className="timeline-meta">{(playback?.currentTimeSec ?? frame.currentTimeSec).toFixed(2)}s · tick {frame.currentTick}</div>
        </section>
        <section className="timeline-card">
          <div className="section-title">Upload queue</div>
          <div className="queue-list">
            {queue.length === 0 && <div className="empty">No uploads queued yet.</div>}
            {queue.slice(0, 8).map((item) => <div key={item.id} className={`queue-row ${item.status}`}><span>{item.demoName}</span><em>{item.status}{item.lastError ? ` · ${item.lastError}` : ''}</em></div>)}
          </div>
        </section>
      </section>
    </main>
  );
}

function App() {
  return window.location.hash.includes('overlay') ? <OverlayRoute /> : <DashboardRoute />;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
