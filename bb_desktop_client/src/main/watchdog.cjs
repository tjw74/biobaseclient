'use strict';

/**
 * Detached remote-kill watchdog — survives main Electron window hangs.
 * Spawned from main with ELECTRON_RUN_AS_NODE=1 and device credentials in env.
 *
 * Env: BIOBASE_DEVICE_ID, BIOBASE_DEVICE_TOKEN, BIOBASE_API_HOST (default cs2.clarionlab.dev)
 *      BIOBASE_APP_VERSION, BIOBASE_HOSTNAME
 */
const { execFile } = require('node:child_process');
const https = require('node:https');
const os = require('node:os');

const POLL_MS = 15_000;
const HOST = (process.env.BIOBASE_API_HOST || 'cs2.clarionlab.dev').trim();
const DEVICE_ID = (process.env.BIOBASE_DEVICE_ID || '').trim();
const DEVICE_TOKEN = (process.env.BIOBASE_DEVICE_TOKEN || '').trim();
const APP_VERSION = (process.env.BIOBASE_APP_VERSION || '0.0.0').trim();
const HOSTNAME = (process.env.BIOBASE_HOSTNAME || os.hostname()).trim();
const LOG_PREFIX = '[biobase-watchdog]';

const CLOSE_OVERLAY_PS = [
  'Add-Type @\'',
  'using System;',
  'using System.Text;',
  'using System.Runtime.InteropServices;',
  'public class WindowHelper {',
  '  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);',
  '  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnum, IntPtr lp);',
  '  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int count);',
  '  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);',
  '  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);',
  '  public const uint WM_CLOSE = 0x0010;',
  '}',
  '\'@',
  '$found = $false',
  '[WindowHelper]::EnumWindows([WindowHelper+EnumWindowsProc]{ param($h,$l)',
  '  $sb = New-Object System.Text.StringBuilder 256',
  '  [void][WindowHelper]::GetWindowText($h, $sb, 256)',
  '  if ($sb.ToString() -eq \'Biobase HUD\' -and [WindowHelper]::IsWindowVisible($h)) {',
  '    [void][WindowHelper]::PostMessage($h, [WindowHelper]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)',
  '    $script:found = $true',
  '  }',
  '  return $true',
  '}, [IntPtr]::Zero) | Out-Null',
  'if ($found) { Write-Output \'closed\' } else { Write-Output \'none\' }',
].join('; ');

function log(message) {
  console.log(`${LOG_PREFIX} ${message}`);
}

function fetchCommands() {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: HOST,
        path: '/admin/api/client/device/commands?scope=watchdog',
        method: 'GET',
        headers: {
          Accept: 'application/json',
          'X-Biobase-Device-Id': DEVICE_ID,
          'X-Biobase-Device-Token': DEVICE_TOKEN,
          'X-Biobase-App-Version': APP_VERSION,
          'X-Biobase-Hostname': HOSTNAME,
        },
        timeout: 12_000,
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => {
          resolve({ status: res.statusCode || 0, body });
        });
      },
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy(new Error('request_timeout'));
    });
    req.end();
  });
}

function runPowerShell(script) {
  return new Promise((resolve, reject) => {
    execFile(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      { windowsHide: true, timeout: 15_000 },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(`${error.message}${stderr ? ` ${stderr}` : ''}`));
          return;
        }
        resolve(String(stdout || '').trim());
      },
    );
  });
}

async function closeOverlayWindows() {
  if (process.platform !== 'win32') {
    log('close_overlay ignored (not Windows)');
    return;
  }
  try {
    const result = await runPowerShell(CLOSE_OVERLAY_PS);
    log(`close_overlay → ${result || 'done'}`);
  } catch (error) {
    log(`close_overlay error: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function killBiobaseClient() {
  if (process.platform !== 'win32') {
    log('kill_app ignored (not Windows)');
    return;
  }
  log('kill_app → taskkill Biobase Client.exe /T');
  execFile(
    'taskkill',
    ['/F', '/IM', 'Biobase Client.exe', '/T'],
    { windowsHide: true },
    (error, _stdout, stderr) => {
      if (error) {
        log(`taskkill error: ${error.message}${stderr ? ` ${stderr}` : ''}`);
        return;
      }
      log('taskkill completed');
    },
  );
}

async function pollOnce() {
  if (!DEVICE_ID || !DEVICE_TOKEN) {
    return;
  }
  try {
    const { status, body } = await fetchCommands();
    if (status === 401) return;
    if (status !== 200) {
      log(`poll http_${status}`);
      return;
    }
    const payload = JSON.parse(body);
    const commands = Array.isArray(payload.commands) ? payload.commands : [];
    for (const entry of commands) {
      if (!entry || !entry.command) continue;
      if (entry.command === 'close_overlay') {
        await closeOverlayWindows();
      } else if (entry.command === 'kill_app') {
        killBiobaseClient();
      }
    }
  } catch (error) {
    log(`poll failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}

if (!DEVICE_ID || !DEVICE_TOKEN) {
  log('missing device credentials — exiting');
  process.exit(0);
}

log(
  `started (poll ${POLL_MS / 1000}s, host ${HOST}, device ${DEVICE_ID.slice(0, 8)}…, v${APP_VERSION}, ${HOSTNAME})`,
);
void pollOnce();
setInterval(() => {
  void pollOnce();
}, POLL_MS);
