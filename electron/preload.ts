import { contextBridge, ipcRenderer } from 'electron';
import type { DatabaseStatus, TodayDashboard } from './database';
import type { getTrackerStatus } from './tracker';

type TrackerStatus = ReturnType<typeof getTrackerStatus>;

export type StryvApi = {
  getDatabaseStatus: () => Promise<DatabaseStatus>;
  getTodayDashboard: () => Promise<TodayDashboard>;
  getTrackerStatus: () => Promise<TrackerStatus>;
  minimizeWindow: () => Promise<void>;
  toggleMaximizeWindow: () => Promise<boolean>;
  closeWindowToTray: () => Promise<void>;
  onTrackerStatusChanged: (callback: (status: TrackerStatus) => void) => () => void;
};

const api: StryvApi = {
  getDatabaseStatus: () => ipcRenderer.invoke('app:getDatabaseStatus'),
  getTodayDashboard: () => ipcRenderer.invoke('dashboard:getToday'),
  getTrackerStatus: () => ipcRenderer.invoke('tracking:getStatus'),
  minimizeWindow: () => ipcRenderer.invoke('window:minimize'),
  toggleMaximizeWindow: () => ipcRenderer.invoke('window:toggleMaximize'),
  closeWindowToTray: () => ipcRenderer.invoke('window:closeToTray'),
  onTrackerStatusChanged: (callback) => {
    const listener = (_event: Electron.IpcRendererEvent, status: TrackerStatus) => callback(status);
    ipcRenderer.on('tracking:statusChanged', listener);

    return () => {
      ipcRenderer.removeListener('tracking:statusChanged', listener);
    };
  },
};

contextBridge.exposeInMainWorld('stryv', api);
