import { contextBridge, ipcRenderer } from 'electron';
import type { DatabaseStatus } from './database';

export type StryvApi = {
  getDatabaseStatus: () => Promise<DatabaseStatus>;
};

const api: StryvApi = {
  getDatabaseStatus: () => ipcRenderer.invoke('app:getDatabaseStatus'),
};

contextBridge.exposeInMainWorld('stryv', api);
