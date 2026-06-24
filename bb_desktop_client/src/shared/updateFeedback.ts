import type { UpdateStatus } from './updateTypes.js';

export function formatVersionClickFeedback(status: UpdateStatus): string {
  if (status.message?.includes('Mac download')) return 'Opening Mac download in your browser…';

  switch (status.state) {
    case 'not-available': {
      const version = status.latestVersion || status.currentVersion;
      return `Latest: v${version} installed`;
    }
    case 'ready':
      return `Update ready: v${status.latestVersion ?? status.currentVersion} — restart to apply`;
    case 'checking':
      return status.message ?? 'Checking for updates…';
    case 'available':
      return status.message ?? `Update available: v${status.latestVersion ?? 'new build'}`;
    case 'downloading':
      return status.message ?? 'Downloading update…';
    case 'error':
      return status.message ? `Update check failed: ${status.message}` : 'Update check failed';
    case 'idle':
    default:
      return 'Update check started';
  }
}
