import os from 'node:os';
import path from 'node:path';

/** Resolve default folders to scan for `.dem` files (platform-aware). */
export function scanRootsForPlatform(
  platform: NodeJS.Platform,
  home: string,
  env: NodeJS.ProcessEnv = process.env,
): string[] {
  const steamCommon = (segments: string[]): string[] => {
    if (platform === 'darwin') {
      const base = path.join(home, 'Library', 'Application Support', 'Steam', 'steamapps', 'common');
      return segments.map((name) => path.join(base, name, 'game', 'csgo'));
    }
    if (platform === 'win32') {
      const roots = [
        path.join(env['PROGRAMFILES(X86)'] ?? 'C:/Program Files (x86)', 'Steam', 'steamapps', 'common'),
        path.join(env.PROGRAMFILES ?? 'C:/Program Files', 'Steam', 'steamapps', 'common'),
      ];
      return roots.flatMap((base) => segments.map((name) => path.join(base, name, 'game', 'csgo')));
    }
    const linuxBases = [
      path.join(home, '.steam', 'steam', 'steamapps', 'common'),
      path.join(home, '.local', 'share', 'Steam', 'steamapps', 'common'),
    ];
    return linuxBases.flatMap((base) => segments.map((name) => path.join(base, name, 'game', 'csgo')));
  };

  const cs2Installs = steamCommon([
    'Counter-Strike Global Offensive',
    'Counter-Strike 2',
  ]);

  const replayDirs = cs2Installs.map((csgo) => path.join(csgo, 'replays'));

  return Array.from(
    new Set([
      ...cs2Installs,
      ...replayDirs,
      path.join(home, 'Documents'),
      path.join(home, 'Downloads'),
    ]),
  );
}

export function defaultScanRoots(): string[] {
  return scanRootsForPlatform(process.platform, os.homedir());
}
