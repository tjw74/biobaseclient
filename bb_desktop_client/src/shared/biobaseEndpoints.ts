import type { ServerConnectInfo } from './liveTypes.js';

/** Public CS2 + admin hostname (DNS → current server; changes with cloud migration). */
export const BIOBASE_CS2_HOST = 'cs2.clarionlab.dev';

export const DEFAULT_API_BASE_URL = `https://${BIOBASE_CS2_HOST}/admin`;

export const DEFAULT_CS2_GAME_PORT = 27015;

/** CS2 Steam app id — used for steam://run/730//+connect … launch. */
export const CS2_STEAM_APP_ID = 730;

/** Remote-safe CS2 launch: borderless windowed so Esc opens menu and mouse is not trapped. */
export const CS2_WINDOWED_LAUNCH_OPTS = '-windowed -noborder';

/** electron-updater generic feed (latest.yml + biobase-client-setup.exe). */
export const DEFAULT_UPDATE_FEED_URL = `https://${BIOBASE_CS2_HOST}/client/`;

/** Browser fallback when in-app updater fails (one-click download page). */
export const MANUAL_INSTALL_URL = `https://${BIOBASE_CS2_HOST}/install`;

/** Mac observer build — zip download (no in-app auto-update yet). */
export const MANUAL_INSTALL_MAC_URL = `https://${BIOBASE_CS2_HOST}/install-mac`;

/** steam://run/730/-windowed -noborder//+connect host:port — windowed + auto-join for remote play. */
export function buildSteamConnectUrl(host: string, port: number): string {
  const trimmedHost = host.trim();
  if (!trimmedHost || !Number.isFinite(port) || port <= 0) {
    throw new Error('invalid_connect_target');
  }
  return `steam://run/${CS2_STEAM_APP_ID}/-windowed%20-noborder//+connect%20${trimmedHost}:${port}`;
}

export function connectInfoFromHostPort(host: string, port: number): ServerConnectInfo {
  const trimmedHost = host.trim();
  return {
    host: trimmedHost,
    port,
    console: `connect ${trimmedHost}:${port}`,
    steamUrl: buildSteamConnectUrl(trimmedHost, port),
  };
}

export const DEFAULT_CONNECT: ServerConnectInfo = connectInfoFromHostPort(BIOBASE_CS2_HOST, DEFAULT_CS2_GAME_PORT);
