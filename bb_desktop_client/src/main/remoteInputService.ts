import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

/** Send Escape to the foreground app (CS2 menu → releases mouse in windowed mode). */
export async function releaseMouseCapture(): Promise<{ ok: true } | { ok: false; error: string }> {
  if (process.platform !== 'win32') {
    return { ok: false, error: 'release_mouse_windows_only' };
  }
  const script = `
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BiobaseKey {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
[BiobaseKey]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
[BiobaseKey]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
`.trim();
  try {
    await execFileAsync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], {
      timeout: 5000,
      windowsHide: true,
    });
    return { ok: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message };
  }
}
