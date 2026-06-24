import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { CS2_STEAM_APP_ID, CS2_WINDOWED_LAUNCH_OPTS } from '../shared/biobaseEndpoints.js';

const execFileAsync = promisify(execFile);

const STEAM_APP_KEY = `HKCU:\\Software\\Valve\\Steam\\Apps\\${CS2_STEAM_APP_ID}`;

/** Persist CS2 windowed/borderless launch options so Esc opens menu and mouse is not trapped. */
export async function ensureCs2WindowedLaunch(): Promise<{ ok: true } | { ok: false; error: string }> {
  if (process.platform !== 'win32') {
    return { ok: true };
  }
  const script = `
$key = '${STEAM_APP_KEY}'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
$want = '${CS2_WINDOWED_LAUNCH_OPTS}'
$cur = (Get-ItemProperty -Path $key -Name LaunchOptions -ErrorAction SilentlyContinue).LaunchOptions
if ($cur -ne $want) {
  Set-ItemProperty -Path $key -Name LaunchOptions -Value $want -Type String -Force
}
`.trim();
  try {
    await execFileAsync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], {
      timeout: 8000,
      windowsHide: true,
    });
    return { ok: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message };
  }
}
