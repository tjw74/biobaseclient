/// <reference types="vite/client" />
import type { ClientSettings, LocalDemoFile, ParsedDemoSummary, PlaybackState, UploadQueueItem } from '../../shared/types';

declare global {
  interface Window {
    biobaseDesktop?: {
      showOverlay: () => Promise<void>;
      hideOverlay: () => Promise<void>;
      scanDemos: () => Promise<LocalDemoFile[]>;
      selectDemo: () => Promise<LocalDemoFile | null>;
      importDemo: (filePath: string) => Promise<LocalDemoFile>;
      parseDemo: (filePath: string) => Promise<ParsedDemoSummary>;
      getPlayback: () => Promise<PlaybackState>;
      setPlayback: (patch: Partial<PlaybackState> & { currentTimeSec?: number }) => Promise<PlaybackState>;
      getSettings: () => Promise<ClientSettings>;
      saveSettings: (patch: Partial<ClientSettings>) => Promise<ClientSettings>;
      getUploadQueue: () => Promise<UploadQueueItem[]>;
      syncUploadQueue: () => Promise<UploadQueueItem[]>;
      uploadParsedSummary: (parsed: ParsedDemoSummary) => Promise<{ item: UploadQueueItem; queue: UploadQueueItem[] }>;
    };
  }
}

export {};
