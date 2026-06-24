import electron from 'electron';
const { app } = electron;
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ClientSettings } from '../shared/types.js';
import { BIOBASE_CS2_HOST } from '../shared/biobaseEndpoints.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const LOG_PREFIX = '[biobase-watchdog]';
let watchdogSpawnedThisSession = false;

function log(message: string) {
  console.log(`${LOG_PREFIX} ${message}`);
}

function watchdogScriptPath(): string {
  const compiled = path.join(__dirname, 'watchdog.cjs');
  if (fs.existsSync(compiled)) return compiled;
  return path.join(__dirname, '../../src/main/watchdog.cjs');
}

export function startRemoteWatchdog(settings: ClientSettings): void {
  if (process.platform !== 'win32') {
    log('skipped — watchdog is Windows-only');
    return;
  }
  if (watchdogSpawnedThisSession) {
    log('skipped — already spawned this session');
    return;
  }
  if (!settings.deviceId || !settings.deviceToken) {
    log('skipped — device not paired');
    return;
  }

  const scriptPath = watchdogScriptPath();
  if (!fs.existsSync(scriptPath)) {
    log(`script missing: ${scriptPath}`);
    return;
  }

  try {
    const child = spawn(process.execPath, [scriptPath], {
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
      env: {
        ...process.env,
        ELECTRON_RUN_AS_NODE: '1',
        BIOBASE_DEVICE_ID: settings.deviceId,
        BIOBASE_DEVICE_TOKEN: settings.deviceToken,
        BIOBASE_API_HOST: BIOBASE_CS2_HOST,
        BIOBASE_APP_VERSION: app.getVersion(),
        BIOBASE_HOSTNAME: os.hostname(),
      },
    });
    child.unref();
    watchdogSpawnedThisSession = true;
    log(`spawned detached pid=${child.pid ?? 'unknown'}`);
  } catch (error) {
    log(`spawn failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}
