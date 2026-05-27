import { contextBridge, ipcRenderer } from 'electron';
import type { DatabaseStatus } from './database';
import type { getTrackerStatus } from './tracker';

type TrackerStatus = ReturnType<typeof getTrackerStatus>;

export type StryvApi = {
  getDatabaseStatus: () => Promise<DatabaseStatus>;
  getTrackerStatus: () => Promise<TrackerStatus>;
  onTrackerStatusChanged: (callback: (status: TrackerStatus) => void) => () => void;
};

const api: StryvApi = {
  getDatabaseStatus: () => ipcRenderer.invoke('app:getDatabaseStatus'),
  getTrackerStatus: () => ipcRenderer.invoke('tracking:getStatus'),
  onTrackerStatusChanged: (callback) => {
    const listener = (_event: Electron.IpcRendererEvent, status: TrackerStatus) => callback(status);
    ipcRenderer.on('tracking:statusChanged', listener);

    return () => {
      ipcRenderer.removeListener('tracking:statusChanged', listener);
    };
  },
};

contextBridge.exposeInMainWorld('stryv', api);
