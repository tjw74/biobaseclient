/// <reference types="vite/client" />
import type { ClientSettings, LocalDemoFile, ParsedDemoSummary, PlaybackState, UploadQueueItem } from '../../shared/types';
import type { LiveMovementStatus, LiveServerStatus } from '../../shared/liveTypes';
import type { UpdateStatus } from '../../shared/updateTypes';

declare const __APP_VERSION__: string;

declare global {
  interface Window {
    biobaseDesktop?: {
      showOverlay: () => Promise<void>;
      hideOverlay: () => Promise<void>;
      toggleOverlay: () => Promise<void>;
      isOverlayVisible: () => Promise<boolean>;
      isOverlayDisabled: () => Promise<boolean>;
      isOverlayKillSwitch: () => Promise<boolean>;
      sendMainHeartbeat: () => Promise<void>;
      scanDemos: () => Promise<LocalDemoFile[]>;
      selectDemo: () => Promise<LocalDemoFile | null>;
      importDemo: (filePath: string) => Promise<LocalDemoFile>;
      parseDemo: (filePath: string) => Promise<ParsedDemoSummary>;
      getPlayback: () => Promise<PlaybackState>;
      setPlayback: (patch: Partial<PlaybackState> & { currentTimeSec?: number }) => Promise<PlaybackState>;
      getSettings: () => Promise<ClientSettings>;
      saveSettings: (patch: Partial<ClientSettings>) => Promise<ClientSettings>;
      pairDevice: (input: { pairingCode: string }) => Promise<{ ok: boolean; settings: ClientSettings; error?: string }>;
      getUploadQueue: () => Promise<UploadQueueItem[]>;
      syncUploadQueue: () => Promise<UploadQueueItem[]>;
      uploadParsedSummary: (parsed: ParsedDemoSummary) => Promise<{ item: UploadQueueItem; queue: UploadQueueItem[] }>;
      resetSettings: () => Promise<ClientSettings>;
      getLiveStatus: () => Promise<LiveServerStatus | null>;
      refreshLiveStatus: () => Promise<LiveServerStatus>;
      startLivePolling: () => Promise<LiveServerStatus | null>;
      stopLivePolling: () => Promise<void>;
      getLiveMovement: () => Promise<LiveMovementStatus | null>;
      refreshLiveMovement: () => Promise<LiveMovementStatus>;
      startMovementPolling: () => Promise<LiveMovementStatus | null>;
      stopMovementPolling: () => Promise<void>;
      getAppVersion: () => Promise<string>;
      getPlatform: () => Promise<NodeJS.Platform>;
      getUpdateStatus: () => Promise<UpdateStatus>;
      checkForUpdates: () => Promise<UpdateStatus>;
      downloadUpdate: () => Promise<UpdateStatus>;
      installUpdate: () => Promise<void>;
      openManualInstall: () => Promise<void>;
      openManualInstallMac: () => Promise<void>;
      triggerUpdate: () => Promise<UpdateStatus>;
      connectCs2: (input?: { host?: string; port?: number }) => Promise<
        { ok: true; url: string; host: string; port: number } | { ok: false; error: string }
      >;
      isCs2Running?: () => Promise<boolean>;
      copyConnectCommand: (input?: { host?: string; port?: number }) => Promise<
        { ok: true; text: string } | { ok: false; error: string }
      >;
      createCs2Shortcut: (input?: { host?: string; port?: number }) => Promise<
        { ok: true; path: string } | { ok: false; error: string }
      >;
      createCompanionLink: () => Promise<
        { ok: boolean; code?: string; url?: string; playerName?: string; expiresAt?: string; error?: string }
      >;
      releaseMouse: () => Promise<{ ok: true } | { ok: false; error: string }>;
      onUpdateStatus: (listener: (status: UpdateStatus) => void) => () => void;
    };
  }
}

export {};
