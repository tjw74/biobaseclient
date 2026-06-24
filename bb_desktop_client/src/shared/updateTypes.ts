export type UpdateState =
  | 'idle'
  | 'checking'
  | 'available'
  | 'not-available'
  | 'downloading'
  | 'ready'
  | 'error';

export interface UpdateStatus {
  currentVersion: string;
  state: UpdateState;
  latestVersion?: string;
  progress?: number;
  message?: string;
}
